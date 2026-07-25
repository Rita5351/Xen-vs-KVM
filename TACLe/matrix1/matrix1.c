/*

  This program is part of the TACLeBench benchmark suite.
  Version V 1.x

  Name: matrix1

  Author: Juan Martinez Velarde

  Function: Generic matrix - multiply benchmarking

    This program performs a matrix multiplication of the form C=AB,
    where A and B are two dimensional matrices of arbitrary dimension.
    The only restriction os that the inner dimension of the arrays must
    be greater than 1.

      A[ X x Y ] * B[ Y x Z ] = C[ X x Z ]

                       |a11     a12     ..      a1y|
                       |a21     a22     ..      a2y|
      matrix A[ X x Y ]= |..      ..      ..     ..  |
                       |a(x-1)1 a(x-1)2 ..  a(x-1)y|
                       |ax1     ax2     ..      axy|


                       |b11     b12     ..     b1z|
                       |b21     b22     ..     b2z|
      matrix B[ Y x Z ]= |..      ..      ..     .. |
                       |b(y-1)1 b(y-1)2 .. b(y-1)z|
                       |by1     by2     ..     byz|

                       |c11     c12     ..     c1z|
                       |c21     c22     ..     c2z|
      matrix C[ X x Z ]= |..      ..      ..     .. |
                       |c(x-1)1 c(x-1)2 .. c(x-1)z|
                       |cx1     cx2     ..     cxz|

      matrix elements are stored as

      A[ X x Y ] = { a11, a12, .. , a1y,
                   a21, a22, .. , a2y,
                   ...,
                   ax1, ax2, .. , axy}

      B[ Y x Z ] = { b11, b21, .., b(y-1)1, by1, b12, b22, .. , b(y-1)z, byz }

      C[ X x Z ] = { c11, c21, .. , c(x-1)1, cx1, c12, c22, .. ,c(x-1)z, cxz }

  Source: DSP-Stone
          http://www.ice.rwth-aachen.de/research/tools-projects/entry/detail/dspstone

  Changes: no major functional changes

  License: may be used, modified, and re-distributed freely

*/

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sched.h>
#include <sys/mman.h>
#include <time.h>
#include <string.h>
#include <getopt.h>
#include <pthread.h>
#include <errno.h>

#define USEC_PER_SEC 1000000
#define NSEC_PER_SEC 1000000000
#define HIST_MAX     1000000 // Maximum latency tracked in the histogram


/*
  Macro definitions
*/

#define X 10 /* first dimension of array A */
#define Y 10 /* second dimension of array A, first dimension of array B */
#define Z 10 /* second dimension of array B */


/*
  Forward declaration of functions
*/

void matrix1_pin_down( int A[  ], int B[  ], int C[  ] );
void matrix1_init( void );
void matrix1_main( void );
int main( int, char** );


/*
  Declaration of global variables
*/

int matrix1_A[ X * Y ];
int matrix1_B[ Y * Z ];
int matrix1_C[ X * Z ];


/*
  Global Configuration
*/

int config_priority = 99;
int config_max_cycles = 10000;
int config_affinity = 1;
int config_lockall = 0;
int config_use_nsecs = 0;
int config_histogram = 0;
char config_histfile[256] = "histogram.txt";

/*
  Thread Statistics struct
*/

struct thread_stat {
  unsigned long cycles;
    long min;
    long max;
    long act;
    double avg;
    long *hist_array;
    long hist_overflow;
    volatile int threadstarted;
};

struct thread_stat tstat;

/* Time calculation utilities */

static inline int64_t calcdiff(struct timespec t1, struct timespec t2) {
    int64_t diff;
    diff = USEC_PER_SEC * (long long)((int) t1.tv_sec - (int) t2.tv_sec);
    diff += ((int) t1.tv_nsec - (int) t2.tv_nsec) / 1000;
    return diff;
}

static inline int64_t calcdiff_ns(struct timespec t1, struct timespec t2) {
    int64_t diff;
    diff = NSEC_PER_SEC * (int64_t)((int) t1.tv_sec - (int) t2.tv_sec);
    diff += ((int) t1.tv_nsec - (int) t2.tv_nsec);
    return diff;
}

/* Worker Thread executing matrix1 */
void *matrix1_thread(void *param) {
    struct sched_param schedp;
    cpu_set_t mask;
    struct timespec start, end;
    int64_t diff;

    /* Set CPU affinity */
    CPU_ZERO(&mask);
    CPU_SET(config_affinity, &mask);
    if (pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask) != 0) {
        fprintf(stderr, "Warning: Could not set CPU affinity to CPU #%d\n", config_affinity);
    }

    /* Set Real-Time Priority */
    memset(&schedp, 0, sizeof(schedp));
    schedp.sched_priority = config_priority;
    if (sched_setscheduler(0, SCHED_FIFO, &schedp) != 0) {
        fprintf(stderr, "Warning: Failed to set priority to %d. Try running with sudo.\n", config_priority);
    }

    tstat.threadstarted = 1;

    /* Continuous tight loop - no interval */
    while (tstat.cycles < config_max_cycles) {
        clock_gettime(CLOCK_MONOTONIC, &start);

        /* Execute target benchmark */
        matrix1_init();
        matrix1_main();

        clock_gettime(CLOCK_MONOTONIC, &end);

        if (config_use_nsecs)
            diff = calcdiff_ns(end, start);
        else
            diff = calcdiff(end, start);

        /* Update Statistics */
        if (diff < tstat.min) tstat.min = diff;
        if (diff > tstat.max) tstat.max = diff;
        tstat.avg += (double)diff;
        tstat.act = diff;

        /* Update Histogram */
        if (config_histogram) {
            if (diff >= config_histogram)
                tstat.hist_overflow++;
            else
                tstat.hist_array[diff]++;
        }

        tstat.cycles++;
    }

    /* Switch back to normal scheduling */
    schedp.sched_priority = 0;
    sched_setscheduler(0, SCHED_OTHER, &schedp);
    
    tstat.threadstarted = -1;
    return NULL;
}

/* Print Histogram to file */
void print_histogram_to_file() {
    FILE *fp = fopen(config_histfile, "w");
    if (!fp) {
        fprintf(stderr, "Error opening histogram file %s\n", config_histfile);
        return;
    }

    fprintf(fp, "# Histogram of matrix1 execution times\n");
    fprintf(fp, "# Unit: %s\n", config_use_nsecs ? "nanoseconds" : "microseconds");
    for (int i = 0; i < config_histogram; i++) {
        if (tstat.hist_array[i] > 0) {
            fprintf(fp, "%06d %06lu\n", i, tstat.hist_array[i]);
        }
    }
    
    fprintf(fp, "# Total Loops: %lu\n", tstat.cycles);
    fprintf(fp, "# Min Latency: %ld\n", tstat.min);
    fprintf(fp, "# Avg Latency: %ld\n", tstat.cycles ? (long)(tstat.avg / tstat.cycles) : 0);
    fprintf(fp, "# Max Latency: %ld\n", tstat.max);
    fprintf(fp, "# Overflows:   %ld\n", tstat.hist_overflow);
    
    fclose(fp);
    printf("\nHistogram written to %s\n", config_histfile);
}

void print_usage() {
    printf("matrix1 benchmark - cyclictest style runner\n");
    printf("Options:\n");
    printf("  -a, --affinity=NUM    Run thread on processor NUM (default 1)\n");
    printf("  -l, --loops=LOOPS     Number of execution loops (default 10000)\n");
    printf("  -m, --mlockall        Lock current and future memory allocations\n");
    printf("  -N, --nsecs           Print results in ns instead of us (default us)\n");
    printf("  -p, --priority=PRIO   Priority of the real-time thread (default 99)\n");
    printf("  -h, --histogram=MAX   Dump latency histogram up to MAX time\n");
    printf("  -f, --histfile=FILE   Filename for histogram dump (default histogram.txt)\n");
}


/*
  Initialization functions
*/

void matrix1_pin_down( int A[  ], int B[  ], int C[  ] )
{
  int i;
  volatile int x = 1;

  _Pragma( "loopbound min 100 max 100" )
  for ( i = 0 ; i < X * Y; i++ )
    A[ i ] = x ;

  _Pragma( "loopbound min 100 max 100" )
  for ( i = 0 ; i < Y * Z ; i++ )
    B[ i ] = x ;

  _Pragma( "loopbound min 100 max 100" )
  for ( i = 0 ; i < X * Z ; i++ )
    C[ i ] = 0 ;
}


void matrix1_init( void )
{
  matrix1_pin_down( &matrix1_A[ 0 ], &matrix1_B[ 0 ], &matrix1_C[ 0 ] );
}

/*
  Return function
*/

int matrix1_return( void )
{
  int i;
  int checksum = 0;

  _Pragma( "loopbound min 100 max 100" )
  for ( i = 0; i < X * Z; i++ )
    checksum += matrix1_C[ i ];

  return ( checksum ==  1000 ? 0 : -1 );
}


/*
  Main functions
*/

void _Pragma ( "entrypoint" ) matrix1_main( void )
{
  register int *p_a = &matrix1_A[ 0 ];
  register int *p_b = &matrix1_B[ 0 ];
  register int *p_c = &matrix1_C[ 0 ];

  register int f, i, k;

  _Pragma( "loopbound min 10 max 10" )
  for ( k = 0; k < Z; k++ ) {
    p_a = &matrix1_A[ 0 ];                /* point to the beginning of array A */

    _Pragma( "loopbound min 10 max 10" )
    for ( i = 0; i < X; i++ ) {
      p_b = &matrix1_B[ k * Y ];          /* take next column */

      *p_c = 0;
      _Pragma( "loopbound min 10 max 10" )
      for ( f = 0; f < Y; f++ ) /* do multiply */
        *p_c += *p_a++ * *p_b++;

      p_c++;
    }
  }
}


// int main( void )
// {
//   matrix1_init();
//   matrix1_main();

//   return matrix1_return();
// }

int main(int argc, char **argv) {
    int c;
    int option_index = 0;
    static struct option long_options[] = {
        {"affinity", required_argument, 0, 'a'},
        {"loops",    required_argument, 0, 'l'},
        {"mlockall", no_argument,       0, 'm'},
        {"nsecs",    no_argument,       0, 'N'},
        {"priority", required_argument, 0, 'p'},
        {"histogram",required_argument, 0, 'h'},
        {"histfile", required_argument, 0, 'f'},
        {"help",     no_argument,       0, '?'},
        {0, 0, 0, 0}
    };

    while ((c = getopt_long(argc, argv, "a:l:mNp:h:f:?", long_options, &option_index)) != -1) {
        switch (c) {
            case 'a': config_affinity = atoi(optarg); break;
            case 'l': config_max_cycles = atoi(optarg); break;
            case 'm': config_lockall = 1; break;
            case 'N': config_use_nsecs = 1; break;
            case 'p': config_priority = atoi(optarg); break;
            case 'h': config_histogram = atoi(optarg); break;
            case 'f': strncpy(config_histfile, optarg, sizeof(config_histfile) - 1); break;
            case '?': print_usage(); exit(0);
        }
    }

    if (config_histogram > HIST_MAX) config_histogram = HIST_MAX;

    /* Memory locking */
    if (config_lockall) {
        if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
            perror("mlockall failed");
        }
    }

    /* Initialize Stats */
    memset(&tstat, 0, sizeof(tstat));
    tstat.min = 1000000000; // sufficiently high max
    
    if (config_histogram) {
        tstat.hist_array = calloc(config_histogram, sizeof(long));
        if (!tstat.hist_array) {
            fprintf(stderr, "Failed to allocate histogram array\n");
            exit(1);
        }
    }

    /* Launch worker thread */
    pthread_t thread;
    if (pthread_create(&thread, NULL, matrix1_thread, NULL) != 0) {  
        perror("Failed to create thread");
        exit(1);
    }

    /* Live Output Loop (Monitor Thread) */
    while (tstat.threadstarted != -1) {
        if (tstat.cycles > 0) {
            char *fmt;
            if (config_use_nsecs)
                fmt = "T: 0 P:%2d C:%7lu Min:%7ld Act:%8ld Avg:%8ld Max:%8ld\n";
            else
                fmt = "T: 0 P:%2d C:%7lu Min:%7ld Act:%5ld Avg:%5ld Max:%8ld\n";

            printf(fmt, config_priority, tstat.cycles, tstat.min, tstat.act,
                   (long)(tstat.avg / tstat.cycles), tstat.max);
            fflush(stdout);
            
            // Rewrite the same line next tick
            if (tstat.cycles < config_max_cycles && tstat.threadstarted != -1) {
                printf("\033[1A");
            }
        }
        usleep(10000); // 10ms refresh rate
    }

    pthread_join(thread, NULL);

    /* Generate Histogram File if requested */
    if (config_histogram) {
        print_histogram_to_file();
        free(tstat.hist_array);
    }

    /* Cleanup mlockall */
    if (config_lockall) {
        munlockall();
    }

    return 0;
}
