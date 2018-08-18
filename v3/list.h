//>>vv main
#ifndef list_h
#define list_h

#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <stdbool.h>

#include <cuda.h>
#include <cuda_runtime.h>

#include "system.h"
#include "config.h"

#define nlcut         0.8e0
#define listmax       64
#define maxn_of_block 128
#define mean_of_block 64

// type define
typedef struct
    {
    int    natom;
    double rx[maxn_of_block];
    double ry[maxn_of_block];
    double radius[maxn_of_block];
    int    tag[maxn_of_block];
    } tponeblock;

typedef struct
    {
    int    nblocks;
    intd   nblock;
    vec_t  dl;
    } tpblockargs;

typedef struct
    {
    tpblockargs args;
    tponeblock  *oneblocks;
    } tpblocks;

typedef struct
    {
    int    nbsum;
    int    nb[listmax];
    double x, y;
    } tponelist;

typedef struct
    {
    int natom;
    tponelist *onelists;
    } tplist;

// variables define
extern tpblocks hdblocks;
extern tplist  *dlist;

// subroutines
void calc_nblocks( tpblocks *thdblocks, box_t tbox );
void recalc_nblocks( tpblocks *thdblocks, box_t tbox );
cudaError_t gpu_make_hypercon( tpblocks thdblocks, vec_t *tdcon, double *tdradius, box_t tbox );
cudaError_t gpu_make_list( tplist thdlist, tpblocks thdblocks, vec_t *tdcon, box_t tbox );
cudaError_t gpu_make_list_fallback( tplist thdlist, vec_t *tdcon, double *tradius, box_t tbox );
bool gpu_check_list( tplist thdlist, vec_t *tdcon, box_t tbox );
int cpu_make_list( tplist tlist, vec_t *tcon, double *tradius, box_t tbox );

#endif
