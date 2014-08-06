#pragma once

#include "dg/algorithm.h"
#include "dg/backend/dz.cuh"

#include "parameters.h"
// #include "geometry_circ.h"
#include "geometry.h"

#ifdef DG_BENCHMARK
#include "dg/backend/timer.cuh"
#endif //DG_BENCHMARK

// #define APAR
namespace eule
{
//diffusive terms (add mu_hat?)
template<class container>
struct Rolkar
{
    Rolkar( const dg::Grid3d<double>& g, Parameters p, solovev::GeomParameters gp):
        p(p),
        gp(gp),
        w3d_( dg::create::w3d(g)), v3d_(dg::create::v3d(g)),
        temp( g.size()),
//         pupil_( dg::evaluate( solovev::Pupil( gp), g))
//         lapiris_( dg::evaluate( solovev::TanhDampingInv(gp ), g)),
        pupil_( dg::evaluate( solovev::TanhDamping(gp ), g))
    {
        LaplacianM_perp = dg::create::laplacianM_perp( g, dg::normed, dg::symmetric);
        LaplacianM_para = dg::create::laplacianM_parallel( g, dg::PER);
    }
    void operator()( const std::vector<container>& x, std::vector<container>& y)
    {
        for( unsigned i=0; i<x.size(); i++)
        {
            dg::blas2::gemv( LaplacianM_perp, x[i], temp);
            dg::blas2::gemv( LaplacianM_perp, temp, y[i]);
            dg::blas1::axpby( -p.nu_perp, y[i], 0., y[i]); // - nu_perp lapl_RZ (lapl_RZ (lnN,U)) //factor MISSING!?!
            
            //additional heavy damping zone
//             dg::blas1::pointwiseDot( lapiris_, temp, temp); //N_i U_i
//             dg::blas1::axpby( 0.1, temp, 1., y[i]); // - nu_lap_perp lapl_RZ (lnN,U) //factor MISSING!?!

            dg::blas2::gemv( LaplacianM_para, x[i], temp);
            dg::blas1::axpby(  p.nu_parallel, temp, 1., y[i]); //-nu_lap_varphi (lnN,U) //
        }
       
        //cut contributions to boundary now with damping on all 4 quantities
        for( unsigned i=0; i<y.size(); i++)
            dg::blas1::pointwiseDot( pupil_, y[i], y[i]);
    }
    const dg::DMatrix& laplacianM()const {return LaplacianM_perp;}
    const container& weights(){return w3d_;}
    const container& precond(){return v3d_;}
    const container& iris(){return pupil_;}

  private:
    void divide( const container& zaehler, const container& nenner, container& result)
    {
        dg::blas1::pointwiseDivide( zaehler, nenner, result);
    }
    const Parameters p;
    const solovev::GeomParameters gp;
    const container w3d_, v3d_;
    container temp;
//     const container lapiris_;
    const container pupil_;
    
    dg::DMatrix LaplacianM_perp;
    dg::DMatrix LaplacianM_para;
};

template< class container=thrust::device_vector<double> >
struct Feltor
{
    typedef std::vector<container> Vector;
    typedef typename container::value_type value_type;
    typedef typename thrust::iterator_system<typename container::iterator>::type MemorySpace;
    //typedef cusp::ell_matrix<int, value_type, MemorySpace> Matrix;
    typedef dg::DMatrix Matrix; //fastest device Matrix (does this conflict with 

    Feltor( const dg::Grid3d<value_type>& g, Parameters p,solovev::GeomParameters gp);

    void exp( const std::vector<container>& src, std::vector<container>& dst, unsigned);

    void log( const std::vector<container>& src, std::vector<container>& dst, unsigned);

    /**
     * @brief Returns phi and psi that belong to the last y in operator()
     *
     * In a multistep scheme this belongs to the point HEAD-1
     * @return phi[0] is the electron and phi[1] the generalized ion potential
     */
    const std::vector<container>& potential( ) const { return phi;}
    //new quantities
    const container& aparallel( ) const { return apar;}
    const std::vector<container>& uparallel( ) const { return u;}



    /**
     * @brief Return the Gamma operator used by this object
     *
     * @return Gamma operator
     */

    void operator()( std::vector<container>& y, std::vector<container>& yp);

    double mass( ) {return mass_;}
    double mass_diffusion( ) {return diff_;}
    double energy( ) {return energy_;}
    double energy_diffusion( ){ return ediff_;}

  private:
    void curve( const container& y, container& target);
    //use chi and omega as helpers to compute square velocity in omega
    const container& compute_vesqr( container& potential);
    //extrapolates and solves for phi[1], then adds square velocity ( omega)
    const container& compute_psi( container& potential);
    const container& polarisation( const std::vector<container>& y); //solves polarisation equation
    const container& induct(const std::vector<container>& y);//solves induction equation

    container chi, omega;
    container apar,rho;

    const container binv, curvR, curvZ, gradlnB;
    const container iris, source, damping;
    const container w3d, v3d, one;
    container curvapar;
    std::vector<container> phi, curvphi, dzphi, expy;
    std::vector<container> dzy, curvy; 
    std::vector<container> arakAN,arakAU,arakAphi,u;

    //matrices and solvers
    Matrix A; 
    dg::DZ<dg::DMatrix, container> dz;
    dg::ArakawaX< dg::DMatrix, container>    arakawa; 
    //dg::Polarisation2dX< thrust::host_vector<value_type> > pol; //note the host vector
    dg::Polarisation< dg::DMatrix, container, container > pol; //note the host vector

    dg::Maxwell<dg::DMatrix,container,container> maxwell;
    dg::Invert<container> invert_maxwell,invert_pol;

    const Parameters p;
    const solovev::GeomParameters gp;

    double mass_, energy_, diff_, ediff_;

};

template< class container>
Feltor< container>::Feltor( const dg::Grid3d<value_type>& g, Parameters p, solovev::GeomParameters gp): 
    chi( g.size(), 0.), omega(chi),
    rho( chi), apar(chi), curvapar(chi),
    binv( dg::evaluate(solovev::Field(gp) , g) ),
    curvR( dg::evaluate( solovev::CurvatureR(gp), g)),
    curvZ( dg::evaluate(solovev::CurvatureZ(gp), g)),
    gradlnB( dg::evaluate(solovev::GradLnB(gp) , g)),
    iris( dg::evaluate( solovev::Pupil( gp), g)),
//     source( dg::evaluate( dg::Gaussian( gp.R_0, 0, p.b, p.b, p.amp_source, 0), g)),
//     source( dg::evaluate( solovev::Gradient(gp), g)),
     source( dg::evaluate(solovev::TanhSource(gp, p.amp_source), g)),
    damping( dg::evaluate( solovev::TanhDamping(gp ), g)), 
    phi( 2, chi), curvphi( phi), dzphi(phi), expy(phi),  
    arakAN( phi), arakAU( phi), arakAphi(phi),u(phi),   
    dzy( 4, chi), curvy(dzy),
    A (dg::create::laplacianM_perp( g, dg::not_normed, dg::symmetric)),
    dz(solovev::Field(gp), g, gp.rk4eps),
    arakawa( g), 
    pol(     g), 
    invert_pol( omega, omega.size(), p.eps_pol), 
    w3d( dg::create::w3d(g)), v3d( dg::create::v3d(g)), one( g.size(), 1.),
    maxwell(A,w3d,v3d, 1.), //sign is already correct!
    invert_maxwell(rho, rho.size(), p.eps_maxwell),
    p(p),
    gp(gp)
{

}
template< class container>
const container& Feltor<container>::compute_vesqr( container& potential)
{
    arakawa.bracketS( potential, potential, chi);
    dg::blas1::pointwiseDot( binv, binv, omega);
    dg::blas1::pointwiseDot( chi, omega, omega);
    return omega;
}
template< class container>
const container& Feltor<container>::compute_psi( container& potential)
{
    dg::blas1::axpby( 1., potential, -0.5, compute_vesqr( potential), phi[1]);
    return phi[1];
}


//computes and modifies expy!!
template<class container>
const container& Feltor< container>::polarisation( const std::vector<container>& y)
{
#ifdef DG_BENCHMARK
    dg::Timer t; 
    t.tic();
#endif
    //compute chi and polarisation
    exp( y, expy, 2);
    dg::blas1::axpby( 1., expy[1], 0., chi); //\chi = a_i \mu_i n_i
    dg::blas1::pointwiseDot( chi, binv, chi);
    dg::blas1::pointwiseDot( chi, binv, chi); //chi/= B^2
    //A = pol.create( chi);
    pol.set_chi( chi);
    thrust::transform( expy[0].begin(), expy[0].end(), expy[0].begin(), dg::PLUS<double>(-1)); //n_e -1
    thrust::transform( expy[1].begin(), expy[1].end(), omega.begin(), dg::PLUS<double>(-1)); //n_i -1
#ifdef DG_BENCHMARK
    t.toc();
    //std::cout<< "Polarisation assembly took "<<t.diff()<<"s\n";
#endif 
    dg::blas1::axpby( -1., expy[0], 1., omega); //n_i-n_e
    unsigned number = invert_pol( pol, phi[0], omega, w3d, v3d);
    if( number == invert_pol.get_max())
        throw dg::Fail( p.eps_pol);
    return phi[0];
}

// #if def APAR
template<class container>
const container& Feltor< container>::induct(const std::vector<container>& y)
{
    dg::blas1::axpby( p.beta/p.mu[0], expy[0], 0., maxwell.chi()); //chi = beta/mu_e N_e
    dg::blas1::axpby(- p.beta/p.mu[1], expy[1], 1., maxwell.chi()); //chi =beta/mu_e N_e-beta/mu_i N_i
    dg::blas1::pointwiseDot( expy[0], y[2], rho);                 //rho = n_e w_e

    dg::blas1::pointwiseDot( expy[1], y[3], omega);               //omega = n_i w_i
    dg::blas1::axpby( -1.,omega , 1., rho);  //rho = -n_i w_i + n_e w_e
    //maxwell = (lap_per - beta*(N_i/hatmu_i - n_e/hatmu_e)) A_parallel 
    //rho=n_e w_e -N_i w_i
    unsigned number = invert_maxwell( maxwell, apar, rho); //omega equals a_parallel
    if( number == invert_maxwell.get_max())
        throw dg::Fail( p.eps_maxwell);
    return apar;
}
// #endif
template< class container>
void Feltor< container>::operator()( std::vector<container>& y, std::vector<container>& yp)
{
    assert( y.size() == 4);
    assert( y.size() == yp.size());
    //compute phi via polarisation
    phi[0] = polarisation( y);
    phi[1] = compute_psi( phi[0]);
    //compute A_parallel via induction and compute U_e and U_i from it
    apar = induct(y);

    //calculate U from Apar and w
    dg::blas1::axpby( 1., y[2], - p.beta/p.mu[0], apar, u[0]); // U_e = w_e -beta/mu_e A_parallel
    dg::blas1::axpby( 1., y[3], - p.beta/p.mu[1], apar, u[1]); // U_i = w_i -beta/mu_i A_parallel

    //update energetics, 2% of total time
    exp( y, expy, 2);
    mass_ = dg::blas2::dot( one, w3d, expy[0] ); //take real ion density which is electron density!!
    double Ue = p.tau[0]*dg::blas2::dot( y[0], w3d, expy[0]); // tau_e n_e ln(n_e)
    double Ui = p.tau[1]*dg::blas2::dot( y[1], w3d, expy[1]);// tau_i n_i ln(n_i)
    double Uphi = 0.5*p.mu[1]*dg::blas2::dot( expy[1], w3d, omega); 
    dg::blas1::pointwiseDot( u[0], u[0], omega); //U_e^2
    double Upare = -0.5*p.mu[0]*dg::blas2::dot( expy[0], w3d, omega); 
    dg::blas1::pointwiseDot(u[1], u[1], omega); //U_i^2
    double Upari =  0.5*p.mu[1]*dg::blas2::dot( expy[1], w3d, omega); 
    arakawa.variation(apar,omega); // (dx A_parallel)^2 + (dy A_parallel)^2
    double Uapar = p.beta*sqrt(dg::blas2::dot( omega, w3d, omega));
    energy_ = Ue + Ui + Uphi + Upare + Upari + Uapar;
    
    
    curve( apar, curvapar); //K(A_parallel)
    dg::blas1::axpby(  1.,  gradlnB,p.beta,  curvapar);  // gradlnB + beta K(A_parallel)
    for( unsigned i=0; i<2; i++)
    {
        //Compute RZ poisson  brackets
        arakawa( y[i], phi[i], yp[i]);  //[lnN,phi]_RZ
        arakawa( u[i], phi[i], yp[i+2]);//[U,phi]_RZ  
        dg::blas1::pointwiseDot( yp[i], binv, yp[i]);                        // dtlnN =1/B [phi,lnN]_RZ
        dg::blas1::pointwiseDot( yp[2+i], binv, yp[2+i]);                    // dtU =1/B [phi,U]_RZ
        // compute A_parallel terms of the parallel derivatuve
        arakawa( apar, y[i], arakAN[i]); // [A_parallel,lnN]_RZ
        arakawa( apar, u[i], arakAU[i]); // [A_parallel,U]_RZ
        arakawa( apar, phi[i], arakAphi[i]); // [A_parallel,phi]_RZ
        dg::blas1::pointwiseDot(arakAN[i],binv,arakAN[i]);   //1/B [A_parallel,lnN]_RZ
        dg::blas1::pointwiseDot(arakAU[i],binv,arakAU[i]);   //1/B [A_parallel,U]_RZ
        dg::blas1::pointwiseDot(arakAphi[i],binv,arakAphi[i]); //1/B [A_parallel,phi]_RZ

        //compute parallel derivatives
        dz(y[i], dzy[i]);     //dz(lnN)
        dz(phi[i], dzphi[i]); //dz(phi)
        dz(u[i], dzy[2+i]);   //dz(U)
        //add A_parallel terms to the parallel derivatives
        dg::blas1::axpby(-p.beta,arakAN[i]   ,1.,dzy[i]);  //= dz lnN -beta/B [A_parallel,lnN ] 
        dg::blas1::axpby(-p.beta,arakAphi[i] ,1.,dzphi[i]);//= dz phi -beta/B [A_parallel,phi ] 
        dg::blas1::axpby(-p.beta,arakAU[i]   ,1.,dzy[2+i]);//= dz U-beta/B [A_parallel,U ] 


        //parallel advection terms
        dg::blas1::pointwiseDot(u[i], dzy[i], omega); //Udz lnN 
        dg::blas1::axpby( -1., omega, 1., yp[i]);                            //dtlnN = dtlnN - Udz lnN
        dg::blas1::axpby( -1., dzy[2+i], 1., yp[i]);                         //dtlnN = dtlnN - dz U
        dg::blas1::pointwiseDot(u[i], curvapar, omega);                     
        dg::blas1::axpby( 1., omega, 1., yp[i]);                            //dtlnN = dtlnN + U dz ln B
        dg::blas1::pointwiseDot(u[i], dzy[2+i], omega);                    
        dg::blas1::axpby( -1., omega, 1., yp[2+i]);                         //dtw = dtw - U dz U

        //parallel force terms
        dg::blas1::axpby( -p.tau[i]/p.mu[i]/p.eps_hat, dzy[i], 1., yp[2+i]); //dtw = dtw - tau/(hat(mu))*dz lnN
        dg::blas1::axpby( -1./p.mu[i]/p.eps_hat, dzphi[i], 1., yp[2+i]);     //dtw = dtw - 1/(hat(mu))*dz phi

        //curvature terms
        curve( y[i], curvy[i]);     //K(N)
        curve( u[i], curvy[2+i]);  //K(U)
        curve( phi[i], curvphi[i]);//K(phi)

        dg::blas1::pointwiseDot( u[i], curvy[2+i], omega); //U K(U)
        dg::blas1::pointwiseDot( u[i], omega, chi); //U^2 K(U)
        dg::blas1::axpby( -p.mu[i]*p.eps_hat, omega, 1., yp[i]);             //dtlnN = dtlnN - (hat(mu)) U K(U)
        dg::blas1::axpby( -0.5*p.mu[i]*p.eps_hat, chi, 1., yp[2+i]);         //dtw = dtw - 0.5 (hat(mu)) U^2 K(U)

        dg::blas1::pointwiseDot(u[i], curvy[i], omega); //U K(ln N)
        dg::blas1::pointwiseDot( u[i], omega, chi); //U^2K(ln N)
        dg::blas1::axpby( -p.tau[i], omega, 1., yp[2+i]);                    //dtw = dtw - tau U K(lnN)
        dg::blas1::axpby( -0.5*p.mu[i]*p.eps_hat, chi, 1., yp[i]);           //dtlnN = dtlnN -0.5mu U^2K(lnN)

        dg::blas1::axpby( -p.tau[i], curvy[i], 1., yp[i]);                   //dtlnN = dtlnN - tau K(lnN)
        dg::blas1::axpby( -2.*p.tau[i], curvy[2+i], 1., yp[2+i]);            //dtw = dtw - 2 tau K(U)
        dg::blas1::axpby( -1., curvphi[i], 1., yp[i]);                       //dtlnN= dtlnN - K(psi)

        dg::blas1::pointwiseDot( u[i], curvphi[i], omega);  //U K(phi)
        dg::blas1::axpby( -0.5, omega, 1., yp[2+i]);                         //dtw = dtw -0.5 U K(psi)


    }
    //add parallel resistivity now explicit
    dg::blas1::pointwiseDot( expy[0], u[0], omega); //N_e U_e 
    dg::blas1::pointwiseDot( expy[1], u[1], chi); //N_i U_i
    dg::blas1::axpby( -1., omega, 1., chi); //J_par = -N_e U_e + N_i U_i
    dg::blas1::pointwiseDivide( chi, expy[0], omega);//J_par/N_e
//         //for 1/N_i
// //         dg::blas1::pointwiseDivide( chi, expy[1], chi); //J_par/N_i    now //J_par/N_e  //n_e instead of n_i
    dg::blas1::axpby( -p.c/p.mu[0]/p.eps_hat, omega, 1., yp[2]);  // dtU_e =- C/hat(mu)_e J_par/N_e
    dg::blas1::axpby( -p.c/p.mu[1]/p.eps_hat, omega, 1., yp[3]);  // dtU_e =- C/hat(mu)_e J_par/N_e
        
    //add parallel diffusion with naive implementation
//     for( unsigned i=0; i<4; i++)
//     {
//         dz(dzy[i], omega); //dz (dz (N,U))
//         dg::blas1::axpby( p.nu_parallel, omega, 1., yp[i]);                     //dt(lnN,U) = dt(lnN,U) + dz (dz (lnN,U))
//     }
    //add particle source to dtN
    for( unsigned i=0; i<2; i++)
    {
        dg::blas1::pointwiseDivide( source, expy[i], omega); //source/N
        dg::blas1::axpby( 1., omega, 1, yp[i]  );       //dtlnN = dtlnN + source/N
    }
    //cut boundary terms 
    for( unsigned i=0; i<2; i++)
    {
//         dg::blas1::pointwiseDivide( damping, expy[i], omega); 
//         dg::blas1::axpby( -1., omega, 1., yp[i]);
//         dg::blas1::pointwiseDot( damping, y[i], omega); 
//         dg::blas1::axpby( -1., omega, 1., yp[i]);
                dg::blas1::pointwiseDot( iris, u[i], u[i]); 

    }
    for( unsigned i=0; i<4; i++) //damping and pupil on N and w
    {
        dg::blas1::pointwiseDot( damping, yp[i], yp[i]); 
        dg::blas1::pointwiseDot( iris, yp[i], yp[i]);
    }
}

template< class container>
void Feltor< container>::curve( const container& src, container& target)
{
    dg::blas2::gemv( arakawa.dx(), src, target); //d_R src
    dg::blas2::gemv( arakawa.dy(), src, omega);  //d_Z src
    dg::blas1::pointwiseDot( curvR, target, target); // C^R d_R src
    dg::blas1::pointwiseDot( curvZ, omega, omega);   // C^Z d_Z src
    dg::blas1::axpby( 1., omega, 1., target ); // (C^R d_R + C^Z d_Z) src
}

template< class container>
void Feltor< container>::exp( const std::vector<container>& y, std::vector<container>& target, unsigned howmany)
{
    for( unsigned i=0; i<howmany; i++)
        thrust::transform( y[i].begin(), y[i].end(), target[i].begin(), dg::EXP<value_type>());
}
template< class container>
void Feltor< container>::log( const std::vector<container>& y, std::vector<container>& target, unsigned howmany)
{
    for( unsigned i=0; i<howmany; i++)
        thrust::transform( y[i].begin(), y[i].end(), target[i].begin(), dg::LN<value_type>());
}


} //namespace eule