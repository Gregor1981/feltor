#ifndef _DG_OPERATOR_MATRIX_
#define _DG_OPERATOR_MATRIX_

#include <cusp/coo_matrix.h>
#include <cusp/multiply.h>
#include "dlt.h"
#include "operator.cuh"

namespace dg
{

///@addtogroup lowlevel
///@{


/**
* @brief Form the tensor product between two operators
*
* Computes C_{ijkl} = op1_{ij}op2_{kl}
* @tparam T The value type
* @tparam n Size of the operators
* @param op1 The left hand side
* @param op2 The right hand side
*
* @return The  tensor product
*/
template< class T, size_t n>
Operator<T, n*n> tensor( const Operator< T, n>& op1, const Operator<T, n>& op2)
{
    Operator<T, n*n> prod;
    for( unsigned i=0; i<n; i++)
        for( unsigned j=0; j<n; j++)
            for( unsigned k=0; k<n; k++)
                for( unsigned l=0; l<n; l++)
                    prod(i*n+k, j*n+l) = op1(i,j)*op2(k,l);
    return prod;
}


//namespace create
//{

//creates 1 x op where 1 is the NxN identity matrix
/**
* @brief Tensor product between Delta and an operator
*
* Can be used to create tensors that operate on each dg-vector entry
* The DG Tensor Product 1 x op
* @tparam T value type
* @tparam n The size of the operator
* @param N Size of the delta operator
* @param op The Operator
*
* @return A newly allocated cusp matrix
*/
template< class T, size_t n>
cusp::coo_matrix<int,T, cusp::host_memory> tensor( unsigned N, const Operator<T,n>& op)
{
    assert( N>0);
    //compute number of nonzeroes in op
    unsigned number =0;
    for( unsigned i=0; i<n; i++)
        for( unsigned j=0; j<n; j++)
            if( op(i,j) != 0)
                number++;
    // allocate output matrix
    cusp::coo_matrix<int, T, cusp::host_memory> A(n*N, n*N, N*number);
    number = 0;
    for( unsigned k=0; k<N; k++)
        for( unsigned i=0; i<n; i++)
            for( unsigned j=0; j<n; j++)
                if( op(i,j) != 0)
                {
                    A.row_indices[number]      = k*n+i;
                    A.column_indices[number]   = k*n+j;
                    A.values[number]           = op(i,j);
                    number++;
                }
    return A;
}


/**
 * @brief Multiply 1d matrices by diagonal block batrices from left and right
 *
 * computes (1xleft)m(1xright)
 * @tparam T value type
 * @tparam n The size of the operator
 * @param left The left hand side
 * @param m The matrix
 * @param right The right hand side
 *
 * @return A newly allocated cusp matrix
 */
template< class T, size_t n>
cusp::coo_matrix<int, T, cusp::host_memory> sandwich( const Operator<T,n>& left,  const cusp::coo_matrix<int, T, cusp::host_memory>& m, const Operator<T,n>& right)
{
    typedef cusp::coo_matrix<int, T, cusp::host_memory> Matrix;
    unsigned N = m.num_rows/n;
    Matrix r = tensor( N, right);
    Matrix l = tensor( N, left);
    Matrix mr(m ), lmr(m);

    cusp::multiply( m, r, mr);
    cusp::multiply( l, mr, lmr);
    return lmr;
}
//sandwich l space matrix to make x space matrix
/**
 * @brief Transforms a 1d matrix in l-space to x-space
 *
 * computes (1xbackward)m(1xforward)
 * @tparam T value type
 * @tparam n The size of the operator
 * @param m The matrix
 *
 * @return A newly allocated cusp matrix containing the x-space version of m
 */
template< class T, size_t n>
cusp::coo_matrix<int, T, cusp::host_memory> sandwich( const cusp::coo_matrix<int, T, cusp::host_memory>& m)
{
    Operator<T, n> forward1d( DLT<n>::forward);
    Operator<T, n> backward1d( DLT<n>::backward);
    return sandwich( backward1d, m, forward1d);
}


///@}

//}//namespace create
    
}//namespace dg

#endif //_DG_OPERATOR_MATRIX_
