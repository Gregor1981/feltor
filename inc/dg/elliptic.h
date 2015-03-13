#pragma once

#include "blas.h"
#include "enums.h"
#include "backend/evaluation.cuh"
#include "backend/derivatives.cuh"
#ifdef MPI_VERSION
#include "backend/mpi_derivatives.h"
#include "backend/mpi_evaluation.h"
#endif


/*! @file 

  Contains the general negative elliptic operator
  */
namespace dg
{

/**
 * @brief Operator that acts as a 2d negative elliptic differential operator
 *
 * @ingroup matrixoperators
 *
 * The term discretized is \f[ -\nabla \cdot ( \chi \nabla_\perp ) \f]
 * where \f$ \nabla_\perp \f$ is the perpendicular gradient. In cartesian 
 * coordinates that means \f[ -\partial_x(\chi\partial_x) - \partial_y(\chi\partial_y)\f]
 * is discretized while in cylindrical coordinates
 * \f[ - \frac{1}{R}\partial_R( R\chi\partial_R) - \partial_Z(\chi\partial_Z)\f]
 * is discretized.
 * @tparam Matrix The Matrix class to use
 * @tparam Vector The Vector class to use
 * @tparam Preconditioner The Preconditioner class to use
 * This class has the SelfMadeMatrixTag so it can be used in blas2::symv functions 
 * and thus in a conjugate gradient solver. 
 * @note The constructors initialize \f$ \chi=1\f$ so that a negative laplacian operator
 * results
 * @attention Pay attention to the negative sign 
 */
template <class Matrix, class Vector, class Preconditioner>
class Elliptic
{
    public:
    /**
     * @brief Construct from Grid
     *
     * @tparam Grid The Grid class. A call to dg::evaluate( one, g) must return an instance of the Vector class, 
     * a call to dg::create::weights(g) and dg::create::inv_weights(g)
     * must return instances of the Preconditioner class and 
     * calls to dg::create::dx( g, no, backward) and jump2d( g, bcx, bcy, no) are made.
     * @param g The Grid, boundary conditions are taken from here
     * @param no Not normed for elliptic equations, normed else
     * @param dir Direction of the right first derivative
     */
    template< class Grid>
    Elliptic( const Grid& g, norm no = not_normed, direction dir = forward): 
        leftx ( dg::create::dx( g, inverse( g.bcx()), no, inverse(dir))),
        lefty ( dg::create::dy( g, inverse( g.bcy()), no, inverse(dir))),
        rightx( dg::create::dx( g, g.bcx(), normed, dir)),
        righty( dg::create::dy( g, g.bcy(), normed, dir)),
        jump  ( dg::create::jump2d( g, g.bcx(), g.bcy(), no )),
        weights_(dg::create::weights(g)), precond_(dg::create::inv_weights(g)), 
        xchi( dg::evaluate( one, g) ), xx(xchi), temp( xx), R(xchi),
        no_(no)
    { 
        if( g.system() == cylindrical)
        {
            R = dg::evaluate( dg::coo1, g);
            dg::blas1::pointwiseDot( R, xchi, xchi); 
        }
    }
    /**
     * @brief Construct from grid and boundary conditions
     *
     * @tparam Grid The Grid class. A call to dg::evaluate( one, g) must return an instance of the Vector class, 
     * a call to dg::create::weights(g) and dg::create::inv_weights(g)
     * must return instances of the Preconditioner class and 
     * calls to dg::create::dx( g, no, backward) and jump2d( g, bcx, bcy, no) are made.
     * @param g The Grid
     * @param bcx boundary condition in x
     * @param bcy boundary contition in y
     * @param no Not normed for elliptic equations, normed else
     * @param dir Direction of the right first derivative (i.e. forward, backward or centered)
     */
    template< class Grid>
    Elliptic( const Grid& g, bc bcx, bc bcy, norm no = not_normed, direction dir = forward): 
        leftx (dg::create::dx( g, inverse(bcx), no, inverse(dir))),
        lefty (dg::create::dy( g, inverse(bcy), no, inverse(dir))),
        rightx(dg::create::dx( g,bcx, normed, dir)),
        righty(dg::create::dy( g,bcy, normed, dir)),
        jump  (dg::create::jump2d( g, bcx, bcy, no)),
        weights_(dg::create::weights(g)), precond_(dg::create::inv_weights(g)),
        xchi( dg::evaluate(one, g)), xx(xchi), temp( xx), R(xchi),
        no_(no)
    { 
        if( g.system() == cylindrical)
        {
            R = dg::evaluate( dg::coo1, g);
            dg::blas1::pointwiseDot( R, xchi, xchi); 
        }
    }

    /**
     * @brief Change Chi 
     *
     * @param chi The new chi
     */
    void set_chi( const Vector& chi)
    {
        xchi = chi;
        dg::blas1::pointwiseDot( R, xchi, xchi); 
    }
    /**
     * @brief Returns the weights used to make the matrix symmetric 
     *
     * @return weights
     */
    const Preconditioner& weights()const {return weights_;}
    /**
     * @brief Returns the preconditioner to use in conjugate gradient
     *
     * In this case inverse weights are the best choice
     * @return inverse weights
     */
    const Preconditioner& precond()const {return precond_;}

    /**
     * @brief Computes the polarisation term
     *
     * @param x left-hand-side
     * @param y result
     */
    void symv( Vector& x, Vector& y) 
    {
        dg::blas2::gemv( rightx, x, temp); //R_x*x 
        dg::blas1::pointwiseDot( xchi, temp, temp); //Chi*R_x*x 
        dg::blas2::gemv( leftx, temp, xx); //L_x*Chi*R_x*x

        dg::blas2::gemv( righty, x, temp);
        dg::blas1::pointwiseDot( xchi, temp, temp);
        dg::blas2::gemv( lefty, temp, y);
        dg::blas1::axpby( -1., xx, -1., y, y); //-D_xx - D_yy 
        
        dg::blas2::symv( jump, x, temp);
        if(no_==normed) //if cartesian then R = 1
            dg::blas1::pointwiseDivide( y, R, y);
        dg::blas1::axpby( +1., temp, 1., y, y); 
    }
    private:
    bc inverse( bc bound)
    {
        if( bound == DIR) return NEU;
        if( bound == NEU) return DIR;
        if( bound == DIR_NEU) return NEU_DIR;
        if( bound == NEU_DIR) return DIR_NEU;
        return PER;
    }
    direction inverse( direction dir)
    {
        if( dir == forward) return backward;
        if( dir == backward) return forward;
        return centered;
    }
    Matrix leftx, lefty, rightx, righty, jump;
    Preconditioner weights_, precond_; //contain coeffs for chi multiplication
    Vector xchi, xx, temp, R;
    norm no_;
};

/**
 * @brief Operator that acts as a 2d negative elliptic differential operator
 *
 * @ingroup matrixoperators
 *
 * The term discretized is 
 * \f[ -\nabla \cdot ( \mathbf \chi  \mathbf \chi \cdot \nabla ) \f]
  In cartesian 
 * coordinates that means 
 * \f[ 
 * \begin{align}
 * g = \chi_x \partial_x f + \chi_y\partial_y f + \chi_z \partial_z f \\
 * -\partial_x(\chi_x g ) - \partial_y(\chi_y g) - \partial_z( \chi_z g)
 *  \end{align}
 *  \f] 
 * is discretized while in cylindrical coordinates
 * \f[ 
 * \begin{align}
 * g = \chi_R \partial_R f + \chi_Z\partial_Z f + \chi_\phi \partial_\phi f \\
 * -\frac{1}{R}\partial_R(R\chi_R g ) - \partial_Z(\chi_Z g) - \partial_\phi( \chi_\phi g)
 *  \end{align}
 *  \f] 
 * is discretized.
 * @tparam Matrix The Matrix class to use
 * @tparam Vector The Vector class to use
 * @tparam Preconditioner The Preconditioner class to use
 * This class has the SelfMadeMatrixTag so it can be used in blas2::symv functions 
 * and thus in a conjugate gradient solver. 
 * @note The constructors initialize \f$ \chi_x = \chi_y = \chi_z=1\f$ 
 * @attention Pay attention to the negative sign 
 */
template<class Matrix, class Vector, class Preconditioner> 
struct GeneralElliptic
{
    /**
     * @brief Construct from Grid
     *
     * @tparam Grid The Grid class. A call to dg::evaluate( one, g) must return an instance of the Vector class, 
     * a call to dg::create::weights(g) and dg::create::inv_weights(g)
     * must return instances of the Preconditioner class and 
     * calls to dg::create::dx( g, no, backward) and jump2d( g, bcx, bcy, no) are made.
     * @param g The Grid, boundary conditions are taken from here
     * @param no Not normed for elliptic equations, normed else
     * @param dir Direction of the right first derivative
     */
    template< class Grid>
    GeneralElliptic( const Grid& g, norm no = not_normed, direction dir = forward): 
        leftx ( dg::create::dx( g, inverse( g.bcx()), no, inverse(dir))),
        lefty ( dg::create::dy( g, inverse( g.bcy()), no, inverse(dir))),
        leftz ( dg::create::dz( g, inverse( g.bcz()), no, inverse(dir))),
        rightx( dg::create::dx( g, g.bcx(), normed, dir)),
        righty( dg::create::dy( g, g.bcy(), normed, dir)),
        rightz( dg::create::dz( g, g.bcz(), normed, dir)),
        jump  ( dg::create::jump3d( g, g.bcx(), g.bcy(), g.bcz(), no )),//use 3d jumps
        weights_(dg::create::weights(g)), precond_(dg::create::inv_weights(g)), 
        xchi( dg::evaluate( one, g) ), ychi( xchi), zchi( xchi), 
        xx(xchi), yy(xx), zz(xx), temp0( xx), temp1(temp0), R(xchi),
        no_(no)
    { 
        if( g.system() == cylindrical)
        {
            R = dg::evaluate( dg::coo1, g);
        }
    }

    /**
     * @brief Set x-component of \f$ chi\f$
     *
     * @param chi new x-component
     */
    void set_x( const Vector& chi)
    {
        xchi = chi;
    }
    /**
     * @brief Set y-component of \f$ chi\f$
     *
     * @param chi new y-component
     */
    void set_y( const Vector& chi)
    {
        ychi = chi;
    }
    /**
     * @brief Set z-component of \f$ chi\f$
     *
     * @param chi new z-component
     */
    void set_z( const Vector& chi)
    {
        zchi = chi;
    }

    /**
     * @brief Set new components for \f$ chi\f$
     *
     * @param chi chi[0] is new x-component, chi[1] the new y-component, chi[2] z-component
     */
    void set( const std::vector<Vector>& chi)
    {
        xchi = chi[0];
        ychi = chi[1];
        zchi = chi[2];
    }

    /**
     * @brief Returns the weights used to make the matrix symmetric 
     *
     * @return weights
     */
    const Preconditioner& weights()const {return weights_;}
    /**
     * @brief Returns the preconditioner to use in conjugate gradient
     *
     * In this case inverse weights are the best choice
     * @return inverse weights
     */
    const Preconditioner& precond()const {return precond_;}

    /**
     * @brief Computes the polarisation term
     *
     * @param x left-hand-side
     * @param y result
     */
    void symv( Vector& x, Vector& y) 
    {
        dg::blas2::gemv( rightx, x, temp0); //R_x*x 
        dg::blas1::pointwiseDot( xchi, temp0, xx); //Chi_x*R_x*x 

        dg::blas2::gemv( righty, x, temp0);//R_y*x
        dg::blas1::pointwiseDot( ychi, temp0, yy);//Chi_y*R_y*x

        dg::blas2::gemv( rightz, x, temp0); // R_z*x
        dg::blas1::pointwiseDot( zchi, temp0, zz); //Chi_z*R_z*x

        dg::blas1::axpby( 1., xx, 1., yy, temp0);
        dg::blas1::axpby( 1., zz, 1., temp0, temp0); //gradpar x 
        dg::blas1::pointwiseDot( R, temp0, temp0);

        dg::blas1::pointwiseDot( xchi, temp0, temp1); 
        dg::blas2::gemv( leftx, temp1, xx); 

        dg::blas1::pointwiseDot( ychi, temp0, temp1);
        dg::blas2::gemv( lefty, temp1, yy);

        dg::blas1::pointwiseDot( zchi, temp0, temp1); 
        dg::blas2::gemv( leftz, temp1, zz); 

        dg::blas1::axpby( -1., xx, -1., yy, y);
        dg::blas1::axpby( -1., zz, +1., y, y); 
        
        dg::blas2::symv( jump, x, temp0);
        if(no_==normed) //if cartesian then R = 1
            dg::blas1::pointwiseDivide( y, R, y);
        dg::blas1::axpby( +1., temp0, 1., y, y); 
    }
    private:
    bc inverse( bc bound)
    {
        if( bound == DIR) return NEU;
        if( bound == NEU) return DIR;
        if( bound == DIR_NEU) return NEU_DIR;
        if( bound == NEU_DIR) return DIR_NEU;
        return PER;
    }
    direction inverse( direction dir)
    {
        if( dir == forward) return backward;
        if( dir == backward) return forward;
        return centered;
    }
    Matrix leftx, lefty, leftz, rightx, righty, rightz, jump;
    Preconditioner weights_, precond_; //contain coeffs for chi multiplication
    Vector xchi, ychi, zchi, xx, yy, zz, temp0, temp1,  R;
    norm no_;
};

///@cond
template< class M, class V, class P>
struct MatrixTraits< Elliptic<M, V, P> >
{
    typedef double value_type;
    typedef SelfMadeMatrixTag matrix_category;
};

template< class M, class V, class P>
struct MatrixTraits< GeneralElliptic<M, V, P> >
{
    typedef double value_type;
    typedef SelfMadeMatrixTag matrix_category;
};
///@endcond

} //namespace dg

