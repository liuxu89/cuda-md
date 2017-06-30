#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include <cuda.h>
#include <cuda_runtime.h>

#include "system.h"
#include "config.h"
#include "list.h"
#include "fire.h"

int main(int argc, const char *argv[])
    {

    cudaSetDevice(0);
    // set
    box.natom = 2000000;
    box.phi = 1.0;
    sets.seed = 201;

    // cpu config
    //printf( "allocate *con, generate a random config\n" );
    alloc_con( &con, &radius, box.natom );
    gen_config( con, radius, &box, sets );

    // md
    init_nvt( con, radius, box, 1.e-4 );

    FILE *fio;
    fio = fopen("con.dat", "w+");
        for ( int i=0; i<box.natom; i++ )
            {
            fprintf( fio, "%16.6e \t %16.6e \t %16.6e \n", con[i].x, con[i].y, radius[i] );
            }
    fclose(fio);

    return 0;
    }
    //// fire on gpu
    //mini_fire_cv( con, radius, box );
