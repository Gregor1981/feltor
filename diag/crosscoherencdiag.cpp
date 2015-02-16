#include <iostream>
#include <fstream>
#include <iomanip>
#include <vector>
#include <string>
#include <algorithm> 

#include "dg/algorithm.h"
#include "dg/backend/interpolation.cuh"
#include "dg/backend/xspacelib.cuh"
#include "dg/functors.h"
#include "file/read_input.h"
#include "file/nc_utilities.h"
#include "feltorSlab/parameters.h"

/**
 * @brief normalizes input vector 
 */ 
void NormalizeToFluc(std::vector<double>& in) {
    double ex= 0.;
    double exx= 0.;
    double ex2= 0.;
    double sigma = 0.;    
    for (unsigned j=0;j<in.size();j++)
    {
        ex+=in[j];
        exx+=in[j]*in[j];
    }
    ex/=in.size();
    exx/=in.size();
    ex2=ex*ex;
    sigma=sqrt(exx-ex2);
    for (unsigned j=0;j<in.size();j++)
    {
        in[j] = (in[j]-  ex)/sigma; 
    }
    std::cout << "Sigma = " <<sigma << " Meanvalue = " << ex << std::endl;
}

int main( int argc, char* argv[])
{

    if( argc != 3)
    {
        std::cerr << "Usage: "<<argv[0]<<" [input.nc] [output.nc]\n";
        return -1;
    }
    std::cout << argv[1]<< " -> "<<argv[2]<<std::endl;   
     file::NC_Error_Handle err;
    int ncid;
    err = nc_open( argv[1], NC_NOWRITE, &ncid);
    ///////////////////read in and show inputfile//////////////////
    size_t length;
    err = nc_inq_attlen( ncid, NC_GLOBAL, "inputfile", &length);
    std::string input( length, 'x');
    err = nc_get_att_text( ncid, NC_GLOBAL, "inputfile", &input[0]); 
    std::cout << "input "<<input<<std::endl;
    const eule::Parameters p(file::read_input( input));
    p.display();  

    unsigned Nhist;
    double Nsigma;
    std::cout << "Nhist = ? (100)" << std::endl;
    std::cin >> Nhist;
    std::cout << "Nsigma = ? (4.0)" << std::endl;
    std::cin >> Nsigma;
    std::vector<double> Nepvec,phipvec; 
//     const unsigned Ninput =p.maxout*;
   ///////////////////////////////////////////////////////////////////////////
    //Grids
    std::cout << "Gathering time data " << std::endl;
    size_t Estart[] = {0};
    size_t Ecount[] = {1};
    err = nc_close(ncid);
    double time=0.;
    int NepID,phipID;
    double Nep,phip;
    unsigned step=0;
    //read in values into vectors
    err = nc_open( argv[1], NC_NOWRITE, &ncid);

    unsigned imin,imax;
    std::cout << "tmin = 0 "<< imin << " tmax =" << p.maxout*p.itstp << std::endl;
    std::cout << "enter new imin(>0) and imax(<maxout):" << std::endl;
    std::cin >> imin >> imax;
    time = imin*p.itstp;
    step = imin;
    for( unsigned i=imin; i<imax; i++)//timestepping
    {
        for( unsigned j=0; j<p.itstp; j++)
        {
            step++;
            Estart[0] = step;
            time += p.dt;

            err = nc_inq_varid(ncid, "Ne_p", &NepID);
            err = nc_get_vara_double( ncid, NepID, Estart, Ecount, &Nep);
            Nepvec.push_back (Nep);
            err = nc_inq_varid(ncid, "phi_p", &phipID);
            err = nc_get_vara_double( ncid, phipID, Estart, Ecount, &phip);


            phipvec.push_back (phip);
        }
        std::cout << "time = "<< time <<  std::endl;
    }
    err = nc_close(ncid);

    std::cout << "Computing Crosscoherence" << std::endl;
//     //normalize grid and compute sigma
    NormalizeToFluc(Nepvec);
    NormalizeToFluc(phipvec);
    dg::Grid1d<double>  g1d1(-Nsigma,Nsigma, 1, Nhist,dg::DIR);
    dg::Grid1d<double>  g1d2(-Nsigma,Nsigma, 1, Nhist,dg::DIR); 
    dg::Grid2d<double>  g2d( -Nsigma,Nsigma,-Nsigma,Nsigma, 1, Nhist,Nhist,dg::DIR,dg::DIR); 
    dg::Histogram<dg::HVec> hist1(g1d1,Nepvec);  
    dg::Histogram<dg::HVec> hist2(g1d2,phipvec);    
    dg::Histogram2D<dg::HVec> hist12(g2d,Nepvec,phipvec);    
    dg::HVec PA1 = dg::evaluate(hist1,g1d1);
    dg::HVec A1 = dg::evaluate(dg::coo1,g1d1);
    dg::HVec PA2= dg::evaluate(hist2,g1d2);
    dg::HVec A2 = dg::evaluate(dg::coo1,g1d2);
    dg::HVec PA1A2= dg::evaluate(hist12,g2d);
    
    //-----------------NC output start
    int dataIDs1[2],dataIDs2[2],dataIDs12[1];
    int dim_ids1[1],dim_ids2[1],dim_ids12[2];
    int ncidout;
    file::NC_Error_Handle errout; 
    errout = nc_create(argv[2],NC_NETCDF4|NC_CLOBBER, &ncidout); 
    //plot 1
    std::cout << "1d plot of Ne"<<std::endl;
    errout = file::define_dimension( ncidout,"Ne_", &dim_ids1[0],  g1d1);
    errout = nc_def_var( ncidout, "P(Ne)",   NC_DOUBLE, 1, &dim_ids1[0], &dataIDs1[0]);
    errout = nc_def_var( ncidout, "Ne",    NC_DOUBLE, 1, &dim_ids1[0], &dataIDs1[1]);
    errout = nc_enddef( ncidout);
    errout = nc_put_var_double( ncidout, dataIDs1[0], PA1.data() );
    errout = nc_put_var_double( ncidout, dataIDs1[1], A1.data() );
    //plot 2
    std::cout << "1d plot of Phi"<<std::endl;
    errout = nc_redef(ncidout);
    errout = file::define_dimension( ncidout,"Phi_", &dim_ids2[0],  g1d2);
    errout = nc_def_var( ncidout, "P(Phi)",   NC_DOUBLE, 1, &dim_ids2[0], &dataIDs2[0]);
    errout = nc_def_var( ncidout, "Phi",    NC_DOUBLE, 1, &dim_ids2[0], &dataIDs2[1]);
    errout = nc_enddef( ncidout);
    errout = nc_put_var_double( ncidout, dataIDs2[0], PA2.data() );
    errout = nc_put_var_double( ncidout, dataIDs2[1], A2.data() );
    //plot12
    std::cout << "2d plot"<<std::endl;
    errout = nc_redef(ncidout);
    dim_ids12[0]=dataIDs1[0];
    dim_ids12[1]=dataIDs2[0];
    errout = file::define_dimensions( ncidout, &dim_ids12[0],  g2d);
    errout = nc_def_var( ncidout, "P(Ne,Phi)",   NC_DOUBLE, 2, &dim_ids12[0], &dataIDs12[0]);
    errout = nc_enddef( ncidout);
    errout = nc_put_var_double( ncidout, dataIDs12[0], PA1A2.data() );
    errout = nc_redef(ncidout);
    nc_close( ncidout);

    return 0;
}

