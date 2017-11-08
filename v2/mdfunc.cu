#include "mdfunc.h"

#define BLOCK_SIZE_256  256
#define BLOCK_SIZE_512  512
#define BLOCK_SIZE_1024 1024

__managed__ double g_fmax;
__managed__ double g_wili;


__global__ void kernel_zero_confv( tpvec *thdconfv, int tnatom )
    {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if ( i < tnatom )
        {
        thdconfv[i].x = 0.0;
        thdconfv[i].y = 0.0;
        }
    }

cudaError_t gpu_zero_confv( tpvec *thdconfv, tpbox tbox )
    {
    const int block_size = 256;
    const int natom = tbox.natom;

    dim3 grids( (natom/block_size)+1, 1, 1 );
    dim3 threads( block_size, 1, 1 );

    kernel_zero_confv <<< grids, threads >>> ( tdconfv, natom );

    check_cuda( cudaDeviceSync() );

    return cudaSuccess;
    }


__global__ void kernel_update_vr( tpvec *thdcon, tpvec *thdconv, tpvec *thdconf, int tnatom, double dt )
    {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;

    if ( i < tnatom )
        {
        tpvec ra, va, fa;

        ra = thdcon[i];
        va = thdconv[i];
        fa = thdconf[i];

        va.x += 0.5 * fa.x * dt;
        va.y += 0.5 * fa.y * dt;
        ra.x += va.x * dt;
        ra.y += va.y * dt;

        thdconv[i] = va;
        thdcon[i]  = ra;
        }
    }

cudaError_t gpu_update_vr( tpvec *thdcon, tpvec *thdconv, tpvec *thdconf, tpbox tbox, double dt)
    {
    const int block_size = 256;

    const int natom = tbox.natom;

    dim3 grids( (natom/block_size)+1, 1, 1 );
    dim3 threads( block_size, 1, 1 );

    kernel_update_vr <<< grids, threads >>> ( thdcon, thdconv, thdconf, natom, dt );

    check_cuda( cudaDeviceSync() );

    return cudaSuccess;
    }


__global__ void kernel_update_v( tpvec *tdconv, tpvec *tdconf, int natom, double hfdt )
    {
    const int i = threadIdx.x + blockIdx.x * blockDim.x;

    if ( i < natom )
        {
        tpvec va, fa;
        va    = thdconv[i];
        fa    = thdconf[i];
        va.x += fa.x * hfdt;
        va.y += fa.y * hfdt;
        tdconv[i] = va;
        }
    }

cudaError_t gpu_update_v( tpvec *thdconv, tpvec *thdconf, tpbox tbox, double dt)
    {
    const int block_size = BLOCK_SIZE_256;

    const int natom = tbox.natom;
    const double hfdt = 0.5 * dt;

    dim3 grids( (natom/block_size)+1, 1, 1 );
    dim3 threads( block_size, 1, 1 );

    kernel_update_v <<< grids, threads >>> ( thdconv, thdconf, natom, hfdt );

    check_cuda( cudaDeviceSync() );

    return cudaSuccess;
    }


__global__ void kernel_calc_force( tpvec *thdconf, tponelist *tonelist, tpvec *thdcon, double *thdradius, int tnatom, double tlx )
    {
    __shared__ double sm_wili;

    const int i = threadIdx.x + blockIdx.x * blockDim.x;

    if ( i >= tnatom )
        return;

    if ( threadIdx.x == 0 )
        sm_wili = 0.0;

    __syncthreads();

    int nbsum = tonelist[i].nbsum;

    tpvec  rai = thdcon[i];
    tpvec  fai = { 0.0, 0.0 };
    double ri  = thdradius[i];
    double wi  = 0.0;

    for ( int jj=0; jj<nbsum; jj++ )
        {
        int j = tonelist[i].nb[jj];

        tpvec raj = thdcon[j];
        // dij equal to raidius of atom j
        double rj = tdradius[j];

        // xij
        raj.x -= rai.x;
        raj.y -= rai.y;
        raj.x -= round(raj.x/lx)*lx;
        raj.y -= round(raj.y/lx)*lx;

        double rij = xj*xj + yj*yj; // rij2
        double dij = ri + rj;

        if ( rij < dij*dij )
            {
            rij = sqrt(rij);

            double Vr = ( 1.0 - rij/dij ) / dij;

            fai.x -= - Vr * raj.x / rij;
            fai.y -= - Vr * raj.y / rij;

            // wili
            wi += - Vr * rij;
            }
        }
    tdconf[i] = fai;

    atomicAdd( &sm_wili, wi );

    __syncthreads();
    if ( threadIdx.x == 0 )
        {
        sm_wili /= 2.0;
        atomicAdd( &g_wili, sm_wili );
        }

    }

cudaError_t gpu_calc_force( tpvec *thdconf, tplist thdlist, tpvec *thdcon, double *thdradius, double *static_press, tpbox tbox )
    {
    const int block_size = 256;

    const int natom = tbox.natom;
    const double lx = tbox.x;

    g_wili = 0.0;
    check_cuda( cudaDeviceSync() );

    dim3 grids( (natom/block_size)+1, 1, 1 );
    dim3 threads( block_size, 1, 1 );

    kernel_calc_force <<< grids, threads >>>( thdconf, thdlist.onelists, tdcon, tdradius, natom, lx );

    check_cuda( cudaDeviceSync() );

    *static_press = g_wili / 2.0 / lx / lx;

    return cudaSuccess;
    }


__global__ void kernel_calc_fmax( tpvec *thdconf, int tnatom )
    {
    __shared__ double block_f[BLOCK_SIZE_256];
    const int tid = threadIdx.x;
    const int i   = threadIdx.x + blockIdx.x * blockDim.x;

    block_f[tid] = 0.0;

    if ( i < natom )
        {
        block_f[tid] = fmax( fabs(tdconf[i].x), fabs(tdconf[i].y) );
        }

    __syncthreads();

    int j = BLOCK_SIZE_256;
    j >>= 1;
    while ( j != 0 )
        {
        if ( tid < j )
            {
            block_f[tid] = fmax( block_f[tid], block_f[tid+j] );
            }
        __syncthreads();
        j >>= 1;
        }

    if ( tid == 0 )
        atomicMax( &g_fmax, block_f[0] );
    }

double gpu_calc_fmax( tpvec *thdconf, tpbox tbox )
    {
    const int block_size = BLOCK_SIZE_256;

    const int natom = tbox.natom;

    g_fmax = 0.0;

    dim3 grids( (natom/block_size)+1, 1, 1);
    dim3 threads( block_size, 1, 1);

    kernel_calc_fmax <<< grids, threads >>> ( thdconf, natom );

    check_cuda( cudaDeviceSync() );

    return gsm_fmax;
    }
