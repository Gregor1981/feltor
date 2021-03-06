
#include <iostream>
#include <iomanip>
#include <sstream>
#include <vector>
#include <string>
#include <fstream>

#include <cusp/print.h>

// #define DG_DEBUG


#include "file/read_input.h"
#include "dg/backend/timer.cuh"
#include "dg/backend/xspacelib.cuh"
#include "solovev.h"
#include "feltor/parameters.h"
#include "init.h"
#include "dg/algorithm.h"

#include "dg/poisson.h"
#include "dg/backend/functions.h"
#include "dg/backend/interpolation.cuh"
#include "draw/host_window.h"
#include "file/nc_utilities.h"
struct InvNormR
{
    InvNormR( solovev::GeomParameters gp): R_0(gp.R_0){}
    double operator()( double R, double Z, double phi)
    {
        return R_0/R;
    }
    
    private:
    double R_0;
}; 

int main( int argc, char* argv[])
{
//     double A,R_0,a, elongation;
//     double psipmin,psipmax;
    unsigned n, Nx, Ny, Nz;

    std::vector<double> c(13);
    //read and store geom data
       std::vector<double> v, v2;
    try{ 
        if( argc==1)
        {
            v = file::read_input( "geometry_params.txt"); 
            v2 = file::read_input( "../feltor/input.txt");

        }
        else
        {
            v = file::read_input( argv[1]); 
            v2 = file::read_input( argv[2]);
        }
    }
    catch (toefl::Message& m) {  
        m.display(); 
        for( unsigned i = 0; i<v.size(); i++)
            std::cout << v[i] << " ";
            std::cout << std::endl;
        return -1;}

    //write parameters from file into variables
    const solovev::GeomParameters gp(v);
    const eule::Parameters p(v2);
    p.display( std::cout);
    gp.display( std::cout);

    double Rmin=gp.R_0-p.boxscaleRm*gp.a;
    double Zmin=-p.boxscaleZm*gp.a*gp.elongation;
    double Rmax=gp.R_0+p.boxscaleRp*gp.a; 
    double Zmax=p.boxscaleZp*gp.a*gp.elongation;
    std::cout << "The grid parameters" <<"\n";
    std::cout  << Rmin<<" rho_s " << Rmax <<" rho_s " << Zmin <<" rho_s " <<Zmax <<" rho_s " <<"\n";
    std::cout << "Type n, Nx, Ny, Nz\n";
    std::cin >> n>> Nx>>Ny>>Nz;
        
    solovev::Field field(gp);
    solovev::Psip psip(gp);
    solovev::PsipR psipR(gp);
    solovev::PsipRR psipRR(gp);  
    solovev::PsipZ psipZ(gp);  
    solovev::PsipZZ psipZZ(gp);   
    solovev::PsipRZ psipRZ(gp);  
    solovev::Ipol ipol(gp);
    solovev::InvB invB(gp);
    solovev::LnB lnB(gp);
    solovev::BR bR(gp);
    solovev::BZ bZ(gp);
    solovev::CurvatureR curvatureR(gp);
    solovev::CurvatureZ curvatureZ(gp);
    solovev::GradLnB gradLnB(gp);
    solovev::Pupil pupil(gp);
    InvNormR invnormr(gp);
    solovev::FieldR fieldR(gp);
    solovev::FieldZ fieldZ(gp);
    solovev::FieldP fieldP(gp);
    solovev::BHatR bhatR(gp);
    solovev::BHatZ bhatZ(gp);
    solovev::BHatP bhatP(gp);
    dg::Grid3d<double> grid( Rmin,Rmax, Zmin,Zmax, 0, 2.*M_PI,n, Nx, Ny,Nz);
    dg::HVec vecR = dg::evaluate( fieldR, grid);
    dg::HVec vecZ = dg::evaluate( fieldZ, grid);
    dg::HVec vecP = dg::evaluate( fieldP, grid);

    file::NC_Error_Handle err;
    int ncid, dim_ids[3];
//     err = nc_create( "geometry.nc", NC_CLOBBER, &ncid);
    err = nc_create( "geometry.nc", NC_NETCDF4|NC_CLOBBER, &ncid);

    err = file::define_dimensions( ncid, dim_ids, grid);
    int vecID[3];
    err = nc_def_var( ncid, "BR", NC_DOUBLE, 3, dim_ids, &vecID[0]);
    err = nc_def_var( ncid, "BZ", NC_DOUBLE, 3, dim_ids, &vecID[1]);
    err = nc_def_var( ncid, "BP", NC_DOUBLE, 3, dim_ids, &vecID[2]);
    err = nc_enddef( ncid);
    err = nc_put_var_double( ncid, vecID[0], vecR.data());
    err = nc_put_var_double( ncid, vecID[1], vecZ.data());
    err = nc_put_var_double( ncid, vecID[2], vecP.data());
    nc_close(ncid);
    std::cout << "-----(0) Check single field by integrating from 0 to 2pi (psi=0 surface)" << "\n";
    thrust::host_vector<double>  in(3);
    thrust::host_vector<double>  out(3);
    in[0]=gp.R_0+gp.a*0.6; 
    in[1]=0.0;
    in[2]=0.0;
    dg::integrateRK4( field, in, out,  2*M_PI, gp.rk4eps);
    
    std::cout <<"Rin =  "<< in[0] <<" Zin =  "<<in[1] <<" sin  = "<<in[2]<<"\n";
    std::cout <<"Rout = "<< out[0]<<" Zout = "<<out[1]<<" sout = "<<out[2]<<"\n";


    
    for (unsigned k=1;k<2;k++) //n iterator
    {
        for (unsigned i=0;i<1;i++) //Nxy iterator
        {
            std::stringstream ss1,ss2;
            ss1 << "dserr1n" <<k*n<<"Nxy"<<pow(2,i)* Nx<<".txt";
            ss2 << "dserr2n" <<k*n<<"Nxy"<<pow(2,i)* Nx<<".txt";
            std::string dserr1fn = ss1.str();
            std::string dserr2fn = ss2.str();
    //         std::cout << dserr1fn;
            std::ofstream dserrfile1((char *) dserr1fn.c_str());
            std::ofstream dserrfile2((char *) dserr2fn.c_str());
            for (unsigned zz=0;zz<1;zz++) //Nz iterator
            {
                std::cout << "n = " << k*n << " Nx = " <<pow(2,i)* Nx << " Ny = " <<pow(2,i)* Ny << " Nz = "<<pow(2,zz)* Nz <<"\n";
                //Similar to feltor grid
                dg::CylindricalGrid<dg::DVec> g3d( Rmin,Rmax, Zmin,Zmax, 0, 2.*M_PI,k*n,pow(2,i)* Nx,pow(2,i)* Ny, pow(2,zz)*Nz,dg::NEU, dg::NEU, dg::PER);
                const dg::DVec w3d = dg::create::volume( g3d);
                dg::DVec pupilongrid = dg::evaluate( pupil, g3d);

                std::cout <<"---------------------------------------------------------------------------------------------" << "\n";
                std::cout <<"-----(1a) test with testfunction  (works for DIR)" << "\n";
                solovev::TestFunction func(gp);
                solovev::DeriTestFunction derifunc(gp);
                std::cout << "Construct parallel  derivative\n";
                dg::Timer t;
                t.tic();
                dg::DDS::FieldAligned dsFA( field, g3d, gp.rk4eps, solovev::PsiLimiter(gp), g3d.bcx()); 
                dg::DDS ds( dsFA, field, dg::normed, dg::centered); //choose bc of grid
                t.toc();
                std::cout << "-----> Creation of parallel Derivative took"<<t.diff()<<"s\n";

                dg::DVec function = dg::evaluate( func, g3d),dsfunc(function);
                dg::DVec diff(g3d.size());

                dg::DVec solution = dg::evaluate( derifunc, g3d);
                ds.set_boundaries( dg::PER, 0, 0);
                ds( function, dsfunc);
                //cut boundaries
//                 dg::blas1::pointwiseDot( pupilongrid, dsfunc, dsfunc);  //damped dsfunc
//                 dg::blas1::pointwiseDot( pupilongrid, solution, solution); //damped dssol

                dg::blas1::axpby( 1., solution, -1., dsfunc,diff);
                double normds = dg::blas2::dot( w3d, dsfunc);
                std::cout << "Norm ds  = "<<sqrt( normds)<<"\n";
                double normsol = dg::blas2::dot( w3d,solution);
                std::cout << "Norm sol = "<<sqrt( normsol)<<"\n";
                double normdiff = dg::blas2::dot( w3d, diff);
                double reldiff=sqrt( normdiff/normsol );
                std::cout << "Rel Diff = "<< reldiff<<"\n";
                  std::cout <<"-----(1b) test parallel derivative created brackets with testfunction  (works for DIR/NEU)" << "\n";
//                 solovev::TestFunction func(psip);
//                 solovev::DeriTestFunction derifunc(gp,psip,psipR,psipZ,ipol,invB);
                std::cout << "-----> Construct parallel  derivative\n";
                t.tic();
                dg::DVec dsRZPhifunction(g3d.size());
                dg::DVec dsR(g3d.size());
                dg::DVec dsZ(g3d.size());
                dg::DVec dsPHI(g3d.size());
                dg::DVec BvecR = dg::evaluate( bhatR, grid);
                dg::DVec BvecZ = dg::evaluate( bhatZ, grid);
                dg::DVec BvecPHI = dg::evaluate( bhatP, grid);

                dg::DMatrix dR   =dg::create::dx( g3d, g3d.bcx(),dg::centered);
                dg::DMatrix dZ   =dg::create::dy( g3d, g3d.bcy(),dg::centered);
                dg::DMatrix dPHI =dg::create::dz( g3d, g3d.bcz(),dg::centered);
                
                dg::blas2::symv( dR, function, dsR);  
                dg::blas2::symv( dZ, function,   dsZ); 
                dg::blas2::symv( dPHI,function, dsPHI); 
                dg::blas1::pointwiseDot(BvecR ,dsR,dsR); //BR*dR f
                dg::blas1::pointwiseDot(BvecZ ,dsZ,dsZ); //BZ*dZ f
                dg::blas1::pointwiseDot(BvecPHI ,dsPHI,dsPHI);//Bphi*dphi f
                
                dg::blas1::axpby(1.,dsR,1.,dsZ,dsRZPhifunction); //BR*dR f + BZ*dZ f
                dg::blas1::axpby(1.,dsPHI,1.,dsRZPhifunction,dsRZPhifunction); //BR*dR f + BZ*dZ f+Bphi*dphi f
                t.toc();

                std::cout << "-----> Creation of parallel Derivative took "<<t.diff()<<"s\n";

                dg::DVec diffRZPhi(g3d.size());

                //cut boundaries
//                 dg::blas1::pointwiseDot( pupilongrid,dsRZPhifunction, dsRZPhifunction);  //damped dsfunc
//                 dg::blas1::pointwiseDot( pupilongrid, solution, solution); //damped dssol

                dg::blas1::axpby( 1., solution, -1., dsRZPhifunction, diffRZPhi);
                double normdsRZPhi = dg::blas2::dot( w3d,  dsRZPhifunction);
                std::cout << "Norm dsRZPhi  = "<<sqrt( normdsRZPhi)<<"\n";
                std::cout << "Norm sol = "<<sqrt( normsol)<<"\n";
                double normdiffRZPhi = dg::blas2::dot( w3d, diffRZPhi);
                double reldiffRZPhi=sqrt( normdiffRZPhi/normsol );
                std::cout << "Rel Diff = "<< reldiffRZPhi<<"\n";
                
                std::cout <<"---------------------------------------------------------------------------------------------" << "\n";
                std::cout <<"-----(2a) test with gradlnb" << "\n";    
                dg::DVec gradLnBsolution = dg::evaluate( gradLnB, g3d);
                dg::DVec lnBongrid = dg::evaluate( lnB, g3d);
                dg::DVec dslnBongrid(g3d.size());
                dg::DVec diff2(g3d.size());
                dg::DVec pupilongradLnBsolution(gradLnBsolution);

                ds(lnBongrid,dslnBongrid);
                
                //cut boundaries
//                 dg::blas1::pointwiseDot( pupilongrid, dslnBongrid, dslnBongrid); 
//                 dg::blas1::pointwiseDot( pupilongrid, gradLnBsolution, pupilongradLnBsolution); 

                dg::blas1::axpby( 1., gradLnBsolution , -1., dslnBongrid,diff2); //diff = gradlnB - ds(ln(B))
                //cut boundaries

                double normds2 = dg::blas2::dot( w3d, dslnBongrid); //=  Integral (gds(ln(B))^2 )
                std::cout << "Norm ds  = "<<sqrt( normds2)<<"\n";
                double normsol2 = dg::blas2::dot( w3d,gradLnBsolution);//=  Integral (gradlnB^2 )
                std::cout << "Norm sol = "<<sqrt( normsol2)<<"\n";
                double normdiff2=dg::blas2::dot( w3d, diff2); //=  Integral ((gradlnB - ds(ln(B)))^2)
                double reldiff2 =sqrt( normdiff2/normsol2 ); ;//=  sqrt(Integral ((gradlnB - ds(ln(B)))^2)/Integral (gradlnB^2 ))
                std::cout << "Rel Diff = "<<reldiff2 <<"\n";
                std::cout <<"-----(2b) test with gradlnb" << "\n";    
                dg::DVec dsRlnB(g3d.size());
                dg::DVec dsZlnB(g3d.size());
                dg::DVec dsPHIlnB(g3d.size());
                dg::DVec dsRZPHIlnB(g3d.size());

                dg::DVec diff2b(g3d.size());
                dg::blas2::symv( dR, lnBongrid, dsRlnB);  
                dg::blas2::symv( dZ, lnBongrid,   dsZlnB); 
                dg::blas2::symv( dPHI,lnBongrid, dsPHIlnB); 
                dg::blas1::pointwiseDot(BvecR ,dsRlnB,dsRlnB); //BR*dR f
                dg::blas1::pointwiseDot(BvecZ ,dsZlnB,dsZlnB); //BZ*dZ f
                dg::blas1::pointwiseDot(BvecPHI ,dsPHIlnB,dsPHIlnB);//Bphi*dphi f
                
                dg::blas1::axpby(1.,dsRlnB,1.,dsZlnB,dsRZPHIlnB); //BR*dR f + BZ*dZ f
                dg::blas1::axpby(1.,dsPHIlnB,1.,dsRZPHIlnB,dsRZPHIlnB); //BR*dR f + BZ*dZ f+Bphi*dphi 
                
                //cut boundaries
//                 dg::blas1::pointwiseDot( pupilongrid, dslnBongrid, dslnBongrid); 
//                 dg::blas1::pointwiseDot( pupilongrid, gradLnBsolution, pupilongradLnBsolution); 

                dg::blas1::axpby( 1., gradLnBsolution , -1.,dsRZPHIlnB,diff2b); //diff = gradlnB - ds(ln(B))
                //cut boundaries

                double normds2b = dg::blas2::dot( w3d,dsRZPHIlnB); //=  Integral (gds(ln(B))^2 )
                std::cout << "Norm ds  = "<<sqrt( normds2b)<<"\n";
//                 double normsol2b = dg::blas2::dot( w3d,pupilongradLnBsolution);//=  Integral (gradlnB^2 )
                std::cout << "Norm sol = "<<sqrt( normsol2)<<"\n";
                double normdiff2b=dg::blas2::dot( w3d, diff2b); //=  Integral ((gradlnB - ds(ln(B)))^2)
                double reldiff2b =sqrt( normdiff2b/normsol2 ); ;//=  sqrt(Integral ((gradlnB - ds(ln(B)))^2)/Integral (gradlnB^2 ))
                std::cout << "Rel Diff = "<<reldiff2b <<"\n";
                std::cout <<"---------------------------------------------------------------------------------------------" << "\n";
                std::cout <<"-----(3) test with gradlnb and with (a) Arakawa and (b) Poisson discretization" << "\n";    
                dg::ArakawaX< dg::CylindricalGrid<dg::DVec>, dg::DMatrix, dg::DVec>    arakawa(g3d); 
                dg::Poisson< dg::CylindricalGrid<dg::DVec>, dg::DMatrix, dg::DVec>     poiss(g3d);
                dg::DVec invBongrid = dg::evaluate( invB, g3d);
                dg::DVec psipongrid = dg::evaluate( psip, g3d);
                dg::DVec invnormrongrid = dg::evaluate( invnormr, g3d);
                dg::DVec arakawasolution(g3d.size());
                dg::DVec poisssolution(g3d.size());
                dg::DVec diff3(g3d.size());
                dg::DVec diff4(g3d.size());
//                 dg::blas1::pointwiseDot( pupilongrid, invnormrongrid, invnormrongrid); 
//                 dg::blas1::pointwiseDot( pupilongrid, invBongrid, invBongrid); 

                arakawa( lnBongrid, psipongrid, arakawasolution); //1/B [B,psip]
                poiss(   lnBongrid, psipongrid, poisssolution); //1/B [B,psip]
                dg::blas1::pointwiseDot( invBongrid, arakawasolution, arakawasolution); //1/B^2 [B,psip]
                dg::blas1::pointwiseDot( invnormrongrid, arakawasolution, arakawasolution); //1/(R B^2) [B,psip]
//                 dg::blas1::pointwiseDot( pupilongrid, arakawasolution, arakawasolution); 

                dg::blas1::pointwiseDot( invBongrid, poisssolution, poisssolution); //    1/B^2 [B,psip]
                dg::blas1::pointwiseDot( invnormrongrid, poisssolution, poisssolution); //1/(R B^2) [B,psip]
//                 dg::blas1::pointwiseDot( pupilongrid, poisssolution, poisssolution); 

                
                dg::blas1::axpby( 1., pupilongradLnBsolution , -1., arakawasolution,diff3);

                double normarak= dg::blas2::dot( w3d, arakawasolution); //=  Integral (gds(ln(B))^2 )
                std::cout << "Norm normarak  = "<<sqrt( normarak)<<"\n";
                double normdiff3=dg::blas2::dot( w3d, diff3); //=  Integral ((gradlnB - ds(ln(B)))^2)
                double reldiff3 =sqrt( normdiff3/normsol2 ); ;//=  sqrt(Integral ((gradlnB - ds(ln(B)))^2)/Integral (gradlnB^2 ))
                std::cout << "Rel Diff = "<<reldiff3 <<"\n";
                
                dg::blas1::axpby( 1., pupilongradLnBsolution , -1., poisssolution,diff4);

                double normpoiss= dg::blas2::dot( w3d, poisssolution); //=  Integral (gds(ln(B))^2 )
                std::cout << "Norm normpoiss  = "<<sqrt( normpoiss)<<"\n";
                double normdiff4=dg::blas2::dot( w3d, diff4); //=  Integral ((gradlnB - ds(ln(B)))^2)
                double reldiff4 =sqrt( normdiff4/normsol2 ); ;//=  sqrt(Integral ((gradlnB - ds(ln(B)))^2)/Integral (gradlnB^2 ))
                std::cout << "Rel Diff = "<<reldiff4 <<"\n";
                
                dserrfile1 << pow(2,zz)*Nz <<" " << reldiff << std::endl;
                dserrfile2 << pow(2,zz)*Nz <<" " << reldiff2 << std::endl;
                std::cout <<"---------------------------------------------------------------------------------------------" << "\n";
                std::cout <<"----(4) test div(B) != 0 (works for NEU)"<<"\n";
                dg::DVec bRongrid = dg::evaluate( fieldR, grid);
                dg::DVec bZongrid = dg::evaluate( fieldZ, grid);
                dg::DVec dRbR(g3d.size());
                dg::DVec dZbZ(g3d.size());                
                dg::DVec invRbR(g3d.size());                
//              //cut boundaries
//                 dg::blas1::pointwiseDot( pupilongrid, bRongrid,bRongrid); 
//                 dg::blas1::pointwiseDot( pupilongrid, bZongrid, bZongrid); 
                invnormrongrid = dg::evaluate( invnormr, g3d);

                dg::DVec divB(g3d.size());                
//                 dg::blas2::gemv( arakawa.dx(), bRongrid, dRbR);
//                 dg::blas2::gemv( arakawa.dy(), bZongrid, dZbZ);
                dg::blas2::gemv( poiss.dxlhs(), bRongrid, dRbR); //d_R B^R
                dg::blas2::gemv( poiss.dylhs(), bZongrid, dZbZ); //d_Z B^Z
                dg::blas1::pointwiseDot( invnormrongrid , bRongrid, invRbR); // R_0/R B^R
                dg::blas1::axpby( 1., dRbR   , 1., dZbZ, divB); //d_R B^R + d_Z B^Z
                dg::blas1::axpby( 1./gp.R_0, invRbR , 1., divB); //( B^R/R/R_0 + d_R B^R + d_Z B^Z)
                dg::blas1::pointwiseDot( pupilongrid, divB, divB);  //cut 

                double normdivB2= dg::blas2::dot( w3d, divB); 
                std::cout << "divB = "<<sqrt( normdivB2)<<"\n";
                std::cout <<"---------------------------------------------------------------------------------------------" << "\n";
                std::cout <<"----(5) test grad_par (psi_p) != 0 (works for NEU)"<<"\n";
                dg::DVec dspsi(g3d.size());
                ds( psipongrid, dspsi);
                double normdspsi = dg::blas2::dot( w3d, dspsi);
                std::cout << "Norm grad_par (psi_p)  = "<<sqrt( normdspsi)<<"\n";
       
             }
            dserrfile1.close();
            dserrfile2.close();
   
        }

    }
    

    return 0;
}
