#pragma once
//#include "solovev.h"

/*!@file
 *
 * Initialize and Damping objects
 */
namespace solovev
{
///@addtogroup profiles
///@{
/**
 * @brief Returns zero outside psipmax and inside psipmin, otherwise 1
     \f[ \begin{cases}
        1  \text{ if } \psi_{p,min} < \psi_p(R,Z) < \psi_{p,max}\\
        0  \text{ else}
     \end{cases}\f]
 */ 
struct Iris
{
    Iris( GeomParameters gp ): 
        gp_(gp),
        psip_(gp) {
        }

    /**
     * @brief 
     \f[ \begin{cases}
        1  \text{ if } \psi_{p,min} < \psi_p(R,Z) < \psi_{p,max}\\
        0  \text{ else}
     \end{cases}\f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmax) return 0.;
        if( psip_(R,Z) < gp_.psipmin) return 0.;
        return 1.;
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};
/**
 * @brief Returns zero outside psipmaxcut otherwise 1
     \f[ \begin{cases}
        0  \text{ if } \psi_p(R,Z) > \psi_{p,maxcut} \\
        1  \text{ else}
     \end{cases}\f]
 */ 
struct Pupil
{
    Pupil( GeomParameters gp): 
        gp_(gp),
        psip_(gp) {
        }
    /**
     * @brief 
     \f[ \begin{cases}
        0  \text{ if } \psi_p(R,Z) > \psi_{p,maxcut} \\
        1  \text{ else}
     \end{cases}\f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmaxcut) return 0.;
        return 1.;
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};
/**
 * @brief Returns psi inside psipmax and psipmax outside psipmax
     \f[ \begin{cases}
        \psi_{p,max}  \text{ if } \psi_p(R,Z) > \psi_{p,max} \\
        \psi_p(R,Z) \text{ else}
     \end{cases}\f]
 */ 
struct PsiPupil
{
    PsiPupil( GeomParameters gp, double psipmax): 
        gp_(gp),
        psipmax_(psipmax),
        psip_(gp) {
        } 
    /**
     * @brief 
     \f[ \begin{cases}
        \psi_{p,max}  \text{ if } \psi_p(R,Z) > \psi_{p,max} \\
        \psi_p(R,Z) \text{ else}
     \end{cases}\f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > psipmax_) return psipmax_;
        return  psip_(R,Z);
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    double psipmax_;
    Psip psip_;
};
/**
 * @brief Sets values to one outside psipmaxcut, zero else
     \f[ \begin{cases}
        1  \text{ if } \psi_p(R,Z) > \psi_{p,maxlim} \\
        0  \text{ else}
     \end{cases}\f]
 *
 */ 
struct PsiLimiter
{
    PsiLimiter( GeomParameters gp): 
        gp_(gp),
        psip_(gp) {
        }

    /**
     * @brief 
     \f[ \begin{cases}
        1  \text{ if } \psi_p(R,Z) > \psi_{p,maxlim} \\
        0  \text{ else}
     \end{cases}\f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmaxlim) return 1.;
        return 0.;
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};



/**
 * @brief Damps the outer boundary in a zone 
 * from psipmaxcut to psipmaxcut+ 4*alpha with a normal distribution
 * Returns 1 inside, zero outside and a gaussian within
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < \psi_{p,max,cut}\\
 0 \text{ if } \psi_p(R,Z) > (\psi_{p,max,cut} + 4\alpha) \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max,cut})^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
 *
 */ 
struct GaussianDamping
{
    GaussianDamping( GeomParameters gp):
        gp_(gp),
        psip_(gp) {
        }
    /**
     * @brief 
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < \psi_{p,max,cut}\\
 0 \text{ if } \psi_p(R,Z) > (\psi_{p,max,cut} + 4\alpha) \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max,cut})^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmaxcut + 4.*gp_.alpha) return 0.;
        if( psip_(R,Z) < (gp_.psipmaxcut)) return 1.;
        return exp( -( psip_(R,Z)-gp_.psipmaxcut)*( psip_(R,Z)-gp_.psipmaxcut)/2./gp_.alpha/gp_.alpha);
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};
/**
 * @brief Damps the inner boundary in a zone 
 * from psipmax to psipmax+ 4*alpha with a normal distribution
 * Returns 1 inside, zero outside and a gaussian within
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < (\psi_{p,max} - 4\alpha)\\
 0 \text{ if } \psi_p(R,Z) > \psi_{p,max} \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max} + 4\alpha)^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
 *
 */ 
struct GaussianProfDamping
{
    GaussianProfDamping( GeomParameters gp):
        gp_(gp),
        psip_(gp) {
        }
    /**
     * @brief 
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < (\psi_{p,max} - 4\alpha)\\
 0 \text{ if } \psi_p(R,Z) > \psi_{p,max} \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max} + 4\alpha)^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmax ) return 0.;
        if( psip_(R,Z) < (gp_.psipmax-4.*gp_.alpha)) return 1.;
        return exp( -( psip_(R,Z)-(gp_.psipmax-4.*gp_.alpha))*( psip_(R,Z)-(gp_.psipmax-4.*gp_.alpha))/2./gp_.alpha/gp_.alpha);
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};
/**
 * @brief Damps the inner boundary in a zone 
 * from psipmax to psipmax+ 4*alpha with a normal distribution
 * Returns 1 inside, zero outside and a gaussian within
 * Additionally cuts if Z < Z_xpoint
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < (\psi_{p,max} - 4\alpha) \\
 0 \text{ if } \psi_p(R,Z) > \psi_{p,max} || Z < -1.1\varepsilon a  \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max})^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
 *
 */ 
struct GaussianProfXDamping
{
    GaussianProfXDamping( GeomParameters gp):
        gp_(gp),
        psip_(gp) {
        }
    /**
     * @brief 
     \f[ \begin{cases}
 1 \text{ if } \psi_p(R,Z) < (\psi_{p,max} - 4\alpha) \\
 0 \text{ if } \psi_p(R,Z) > \psi_{p,max} \text{ or } Z < -1.1\varepsilon a  \\
 \exp\left( - \frac{(\psi_p - \psi_{p,max})^2}{2\alpha^2}\right), \text{ else}
 \end{cases}
   \f]
     */
    double operator( )(double R, double Z)
    {
        if( psip_(R,Z) > gp_.psipmax || Z<-1.1*gp_.elongation*gp_.a) return 0.;
        if( psip_(R,Z) < (gp_.psipmax-4.*gp_.alpha)) return 1.;
        return exp( -( psip_(R,Z)-(gp_.psipmax-4.*gp_.alpha))*( psip_(R,Z)-(gp_.psipmax-4.*gp_.alpha))/2./gp_.alpha/gp_.alpha);
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};

/**
 * @brief source for quantities N ... dtlnN = ...+ source/N
 * Returns a tanh profile shifted to \f$ \psi_{p,min}-3\alpha\f$
 \f[ 0.5\left( 1 + \tanh\left( -\frac{\psi_p(R,Z) - \psi_{p,min} + 3\alpha}{\alpha}\right)\right) \f]
 */
struct TanhSource
{
        TanhSource( GeomParameters gp):
        gp_(gp),
        psip_(gp) {
        }
    /**
     * @brief \f[ 0.5\left( 1 + \tanh\left( -\frac{\psi_p(R,Z) - \psi_{p,min} + 3\alpha}{\alpha}\right)\right)
   \f]
     */
    double operator( )(double R, double Z)
    {
        return 0.5*(1.+tanh(-(psip_(R,Z)-gp_.psipmin + 3.*gp_.alpha)/gp_.alpha) );
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return 0.5*(1.+tanh(-(psip_(R,Z,phi)-gp_.psipmin + 3.*gp_.alpha)/gp_.alpha) );
    }
    private:
    GeomParameters gp_;
    Psip psip_;
};

// struct Gradient
// {
//     Gradient(  eule::Parameters p, GeomParameters gp):
//         p_(p),
//         gp_(gp),
//         psip_(gp) {
//     }
//     double operator( )(double R, double Z)
//     {
//         if( psip_(R,Z) < (gp_.psipmin)) return p_.nprofileamp+p_.bgprofamp;
//         if( psip_(R,Z) < 0.) return p_.nprofileamp+p_.bgprofamp-(gp_.psipmin-psip_(R,Z))*(p_.nprofileamp/gp_.psipmin);
//         return p_.bgprofamp;
//     }
//     double operator( )(double R, double Z, double phi)
//     {
//         return (*this)(R,Z);
// 
//     }
//     private:
//     eule::Parameters p_;
//     GeomParameters gp_;
//     Psip psip_;
// };

/**
 * @brief Returns density profile with variable peak amplitude and background amplitude 
     *\f[ N(R,Z)=\begin{cases}
 A_{bg} + A_{peak}\frac{\psi_p(R,Z)} {\psi_p(R_0, 0)} \text{ if }\psi_p < \psi_{p,max} \\
 A_{bg} \text{ else } 
 \end{cases}
   \f]
 */ 
struct Nprofile
{
     Nprofile( double bgprofamp, double peakamp, GeomParameters gp):
         bgamp(bgprofamp), namp( peakamp),
         gp_(gp),
         psip_(gp) { }
    /**
     * @brief \f[ N(R,Z)=\begin{cases}
 A_{bg} + A_{peak}\frac{\psi_p(R,Z)} {\psi_p(R_0, 0)} \text{ if }\psi_p < \psi_{p,max} \\
 A_{bg} \text{ else } 
 \end{cases}
   \f]
     */
   double operator( )(double R, double Z)
    {
        if (psip_(R,Z)<gp_.psipmax) 
            return bgamp +(psip_(R,Z)/psip_(gp_.R_0,0.0)*namp);
        return bgamp;
    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator( )(double R, double Z, double phi)
    {
        return (*this)(R,Z);
    }
    private:
    double bgamp, namp;
    GeomParameters gp_;
    Psip psip_;
};

/**
 * @brief returns zonal flow field 
     \f[ N(R,Z)=\begin{cases}
    A_{bg} |\cos(2\pi\psi_p(R,Z) k_\psi)| \text{ if }\psi_p < \psi_{p,max} \\
    0 \text{ else } 
 \end{cases}
   \f]
 */ 
struct ZonalFlow
{
    ZonalFlow(  double amplitude, double k_psi, GeomParameters gp):
        amp_(amplitude), k_(k_psi),
        gp_(gp),
        psip_(gp) { }
    /**
     * @brief \f[ N(R,Z)=\begin{cases}
 A_{bg} |\cos(2\pi\psi_p(R,Z) k_\psi)| \text{ if }\psi_p < \psi_{p,max} \\
  0 \text{ else } 
 \end{cases}
   \f]
     */
    double operator() (double R, double Z)
    {
      if (psip_(R,Z)<gp_.psipmax) 
          return (amp_*fabs(cos(2.*M_PI*psip_(R,Z)*k_)));
      return 0.;

    }
    /**
    * @brief == operator()(R,Z)
    */
    double operator() (double R, double Z,double phi)
    {
        return (*this)(R,Z);
    }
    private:
    double amp_, k_;
    GeomParameters gp_;
    Psip psip_;
};

/**
 * @brief testfunction to test the parallel derivative 
      \f[ f(R,Z,\varphi) = -\frac{\cos(\varphi)}{R\hat b_\varphi} \f]
 */ 
struct TestFunction
{
    TestFunction( GeomParameters gp) :  
        gp_(gp),
        bhatR_(gp),
        bhatZ_(gp),
        bhatP_(gp) {}
    /**
     * @brief \f[ f(R,Z,\varphi) = -\frac{\cos(\varphi)}{R\hat b_\varphi} \f]
     */ 
    double operator()( double R, double Z, double phi)
    {
//         return psip_(R,Z,phi)*sin(phi);
//         double Rmin = gp_.R_0-(p_.boxscaleRm)*gp_.a;
//         double Rmax = gp_.R_0+(p_.boxscaleRp)*gp_.a;
//         double kR = 1.*M_PI/(Rmax - Rmin);
//         double Zmin = -(p_.boxscaleZm)*gp_.a*gp_.elongation;
//         double Zmax = (p_.boxscaleZp)*gp_.a*gp_.elongation;
//         double kZ = 1.*M_PI/(Zmax - Zmin);
        double kP = 1.;
//         return sin(phi*kP)*sin((R-Rmin)*kR)*sin((Z-Zmin)*kZ); //DIR
//         return cos(phi)*cos((R-Rmin)*kR)*cos((Z-Zmin)*kZ);
//         return sin(phi*kP); //DIR
//         return cos(phi*kP); //NEU
        return -cos(phi*kP)/bhatP_(R,Z,phi)/R; //NEU 2

    }
    private:
    GeomParameters gp_;
    BHatR bhatR_;
    BHatZ bhatZ_;
    BHatP bhatP_;
};
/**
 * @brief analyitcal solution of the parallel derivative of the testfunction
 *  \f[ \nabla_\parallel(R,Z,\varphi) f = \frac{\sin(\varphi)}{R}\f]
 */ 
struct DeriTestFunction
{
    DeriTestFunction( GeomParameters gp) :
        gp_(gp),
        bhatR_(gp),
        bhatZ_(gp),
        bhatP_(gp) {}
/**
 * @brief \f[ \nabla_\parallel f = \frac{\sin(\varphi)}{R}\f]
 */ 
    double operator()( double R, double Z, double phi)
    {
//         double Rmin = gp_.R_0-(p_.boxscaleRm)*gp_.a;
//         double Rmax = gp_.R_0+(p_.boxscaleRp)*gp_.a;
//         double kR = 1.*M_PI/(Rmax - Rmin);
//         double Zmin = -(p_.boxscaleZm)*gp_.a*gp_.elongation;
//         double Zmax = (p_.boxscaleZp)*gp_.a*gp_.elongation;
//         double kZ = 1.*M_PI/(Zmax - Zmin);
        double kP = 1.;
//          return (bhatR_(R,Z,phi)*sin(phi)*sin((Z-Zmin)*kZ)*cos((R-Rmin)*kR)*kR+
//                 bhatZ_(R,Z,phi)*sin(phi)*sin((R-Rmin)*kR)*cos((Z-Zmin)*kZ)*kZ+
//                 bhatP_(R,Z,phi)*cos(phi)*sin((R-Rmin)*kR)*sin((Z-Zmin)*kZ)*kP); //DIR
//         return -bhatR_(R,Z,phi)*cos(phi)*cos((Z-Zmin)*kZ)*sin((R-Rmin)*kR)*kR-
//                bhatZ_(R,Z,phi)*cos(phi)*cos((R-Rmin)*kR)*sin((Z-Zmin)*kZ)*kZ-
//                bhatP_(R,Z,phi)*sin(phi)*cos((R-Rmin)*kR)*cos((Z-Zmin)*kZ)*kP;
//         return  bhatP_(R,Z,phi)*cos(phi*kP)*kP; //DIR
//         return  -bhatP_(R,Z,phi)*sin(phi*kP)*kP; //NEU
        return sin(phi*kP)*kP/R; //NEU 2

    }
    private:
    GeomParameters gp_;
    BHatR bhatR_;
    BHatZ bhatZ_;
    BHatP bhatP_;
};


///@}
}//namespace solovev

