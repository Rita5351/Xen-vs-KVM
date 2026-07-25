/*

  This program is part of the TACLeBench benchmark suite.
  Version V 2.0

  Name: test3

  Author: Rathijit Sen

  Function: This testcase walks through parts of 8 arrays in a 10 x 10 grid of
    functions. function f_i_j calls f_i_j+1 and f_i+1,j except at the grid
    boundaries.

  Source: Universitaet des Saarlandes, Saarbruecken, Germany
          Compiler Research Group

  Original name: test3

  Changes:
          26-10-2007 Creation at Saarbruecken

  License: GPL

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
  Forward declaration of functions
*/

void test3_initSeed();
int test3_randomInteger( void );
void test3_init( void );
int test3_return( void );
void test3_func_10_10( void );
void test3_func_9_10( void );
void test3_func_8_10( void );
void test3_func_7_10( void );
void test3_func_6_10( void );
void test3_func_5_10( void );
void test3_func_4_10( void );
void test3_func_3_10( void );
void test3_func_2_10( void );
void test3_func_1_10( void );
void test3_func_0_10( void );
void test3_func_10_9( void );
void test3_func_9_9( void );
void test3_func_8_9( void );
void test3_func_7_9( void );
void test3_func_6_9( void );
void test3_func_5_9( void );
void test3_func_4_9( void );
void test3_func_3_9( void );
void test3_func_2_9( void );
void test3_func_1_9( void );
void test3_func_0_9( void );
void test3_func_10_8( void );
void test3_func_9_8( void );
void test3_func_8_8( void );
void test3_func_7_8( void );
void test3_func_6_8( void );
void test3_func_5_8( void );
void test3_func_4_8( void );
void test3_func_3_8( void );
void test3_func_2_8( void );
void test3_func_1_8( void );
void test3_func_0_8( void );
void test3_func_10_7( void );
void test3_func_9_7( void );
void test3_func_8_7( void );
void test3_func_7_7( void );
void test3_func_6_7( void );
void test3_func_5_7( void );
void test3_func_4_7( void );
void test3_func_3_7( void );
void test3_func_2_7( void );
void test3_func_1_7( void );
void test3_func_0_7( void );
void test3_func_10_6( void );
void test3_func_9_6( void );
void test3_func_8_6( void );
void test3_func_7_6( void );
void test3_func_6_6( void );
void test3_func_5_6( void );
void test3_func_4_6( void );
void test3_func_3_6( void );
void test3_func_2_6( void );
void test3_func_1_6( void );
void test3_func_0_6( void );
void test3_func_10_5( void );
void test3_func_9_5( void );
void test3_func_8_5( void );
void test3_func_7_5( void );
void test3_func_6_5( void );
void test3_func_5_5( void );
void test3_func_4_5( void );
void test3_func_3_5( void );
void test3_func_2_5( void );
void test3_func_1_5( void );
void test3_func_0_5( void );
void test3_func_10_4( void );
void test3_func_9_4( void );
void test3_func_8_4( void );
void test3_func_7_4( void );
void test3_func_6_4( void );
void test3_func_5_4( void );
void test3_func_4_4( void );
void test3_func_3_4( void );
void test3_func_2_4( void );
void test3_func_1_4( void );
void test3_func_0_4( void );
void test3_func_10_3( void );
void test3_func_9_3( void );
void test3_func_8_3( void );
void test3_func_7_3( void );
void test3_func_6_3( void );
void test3_func_5_3( void );
void test3_func_4_3( void );
void test3_func_3_3( void );
void test3_func_2_3( void );
void test3_func_1_3( void );
void test3_func_0_3( void );
void test3_func_10_2( void );
void test3_func_9_2( void );
void test3_func_8_2( void );
void test3_func_7_2( void );
void test3_func_6_2( void );
void test3_func_5_2( void );
void test3_func_4_2( void );
void test3_func_3_2( void );
void test3_func_2_2( void );
void test3_func_1_2( void );
void test3_func_0_2( void );
void test3_func_10_1( void );
void test3_func_9_1( void );
void test3_func_8_1( void );
void test3_func_7_1( void );
void test3_func_6_1( void );
void test3_func_5_1( void );
void test3_func_4_1( void );
void test3_func_3_1( void );
void test3_func_2_1( void );
void test3_func_1_1( void );
void test3_func_0_1( void );
void test3_func_10_0( void );
void test3_func_9_0( void );
void test3_func_8_0( void );
void test3_func_7_0( void );
void test3_func_6_0( void );
void test3_func_5_0( void );
void test3_func_4_0( void );
void test3_func_3_0( void );
void test3_func_2_0( void );
void test3_func_1_0( void );
void test3_func_0_0( void );
void test3_main( void );
int main( int, char** );

/*
  Declaration of global variables
*/

volatile int test3_seed;
int test3_array1[ 32 ][ 32 ];
int test3_array2[ 32 ][ 32 ];
int test3_array3[ 32 ][ 32 ];
int test3_array4[ 32 ][ 32 ];
int test3_array5[ 32 ][ 32 ];
int test3_array6[ 32 ][ 32 ];
int test3_array7[ 32 ][ 32 ];
int test3_array8[ 32 ][ 32 ];
int test3_result;

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

/* Worker Thread executing test3 */
void *test3_thread(void *param) {
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
        test3_init();
        test3_main();

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

    fprintf(fp, "# Histogram of test3 execution times\n");
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
    printf("test3 benchmark - cyclictest style runner\n");
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
  Initialization- and return-value-related functions
*/

/*
  test3_initSeed initializes the seed used in the "random" number generator.
*/
void test3_initSeed()
{
  test3_seed = 0;
}


/*
  test3_RandomInteger generates random integers between 0 and 8094.
*/
int test3_randomInteger()
{
  test3_seed = ( ( test3_seed * 133 ) + 81 ) % 8095;
  return ( test3_seed );
}


void test3_init( void )
{
  int i, j;


  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array1[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array2[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array3[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array4[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array5[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array6[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array7[ i ][ j ] = test3_randomInteger();

  _Pragma( "loopbound min 32 max 32" )
  for ( i = 0; i < 32; i++ )
    _Pragma( "loopbound min 32 max 32" )
    for ( j = 0; j < 32; j++ )
      test3_array8[ i ][ j ] = test3_randomInteger();

  test3_result = 0;
}


int test3_return( void )
{
  return ( test3_result );
}


/*
  Algorithm core functions
*/

void test3_func_10_10( void )
{
  int i, x;
  int *p = &test3_array5[ 10 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_10( void )
{
  int i, x;
  int *p = &test3_array4[ 9 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_10();
}


void test3_func_8_10( void )
{
  int i, x;
  int *p = &test3_array3[ 8 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_10();
}


void test3_func_7_10( void )
{
  int i, x;
  int *p = &test3_array2[ 7 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_10();
}


void test3_func_6_10( void )
{
  int i, x;
  int *p = &test3_array1[ 6 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_10();
}


void test3_func_5_10( void )
{
  int i, x;
  int *p = &test3_array8[ 5 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_10();
}


void test3_func_4_10( void )
{
  int i, x;
  int *p = &test3_array7[ 4 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_10();
}


void test3_func_3_10( void )
{
  int i, x;
  int *p = &test3_array6[ 3 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_10();
}


void test3_func_2_10( void )
{
  int i, x;
  int *p = &test3_array5[ 2 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_10();
}


void test3_func_1_10( void )
{
  int i, x;
  int *p = &test3_array4[ 1 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_10();
}


void test3_func_0_10( void )
{
  int i, x;
  int *p = &test3_array3[ 0 ][ 10 ];


  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_10();
}


void test3_func_10_9( void )
{
  int i, x;
  int *p = &test3_array4[ 10 ][ 9 ];


  test3_func_10_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_9( void )
{
  int i, x;
  int *p = &test3_array3[ 9 ][ 9 ];


  test3_func_9_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_9();
}


void test3_func_8_9( void )
{
  int i, x;
  int *p = &test3_array2[ 8 ][ 9 ];


  test3_func_8_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_9();
}


void test3_func_7_9( void )
{
  int i, x;
  int *p = &test3_array1[ 7 ][ 9 ];


  test3_func_7_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_9();
}


void test3_func_6_9( void )
{
  int i, x;
  int *p = &test3_array8[ 6 ][ 9 ];


  test3_func_6_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_9();
}


void test3_func_5_9( void )
{
  int i, x;
  int *p = &test3_array7[ 5 ][ 9 ];


  test3_func_5_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_9();
}


void test3_func_4_9( void )
{
  int i, x;
  int *p = &test3_array6[ 4 ][ 9 ];


  test3_func_4_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_9();
}


void test3_func_3_9( void )
{
  int i, x;
  int *p = &test3_array5[ 3 ][ 9 ];


  test3_func_3_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_9();
}


void test3_func_2_9( void )
{
  int i, x;
  int *p = &test3_array4[ 2 ][ 9 ];


  test3_func_2_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_9();
}


void test3_func_1_9( void )
{
  int i, x;
  int *p = &test3_array3[ 1 ][ 9 ];


  test3_func_1_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_9();
}


void test3_func_0_9( void )
{
  int i, x;
  int *p = &test3_array2[ 0 ][ 9 ];


  test3_func_0_10();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_9();
}


void test3_func_10_8( void )
{
  int i, x;
  int *p = &test3_array3[ 10 ][ 8 ];


  test3_func_10_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_8( void )
{
  int i, x;
  int *p = &test3_array2[ 9 ][ 8 ];


  test3_func_9_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_8();
}


void test3_func_8_8( void )
{
  int i, x;
  int *p = &test3_array1[ 8 ][ 8 ];


  test3_func_8_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_8();
}


void test3_func_7_8( void )
{
  int i, x;
  int *p = &test3_array8[ 7 ][ 8 ];


  test3_func_7_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_8();
}


void test3_func_6_8( void )
{
  int i, x;
  int *p = &test3_array7[ 6 ][ 8 ];


  test3_func_6_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_8();
}


void test3_func_5_8( void )
{
  int i, x;
  int *p = &test3_array6[ 5 ][ 8 ];


  test3_func_5_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_8();
}


void test3_func_4_8( void )
{
  int i, x;
  int *p = &test3_array5[ 4 ][ 8 ];


  test3_func_4_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_8();
}


void test3_func_3_8( void )
{
  int i, x;
  int *p = &test3_array4[ 3 ][ 8 ];


  test3_func_3_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_8();
}


void test3_func_2_8( void )
{
  int i, x;
  int *p = &test3_array3[ 2 ][ 8 ];


  test3_func_2_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_8();
}


void test3_func_1_8( void )
{
  int i, x;
  int *p = &test3_array2[ 1 ][ 8 ];


  test3_func_1_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_8();
}


void test3_func_0_8( void )
{
  int i, x;
  int *p = &test3_array1[ 0 ][ 8 ];


  test3_func_0_9();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_8();
}


void test3_func_10_7( void )
{
  int i, x;
  int *p = &test3_array2[ 10 ][ 7 ];


  test3_func_10_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_7( void )
{
  int i, x;
  int *p = &test3_array1[ 9 ][ 7 ];


  test3_func_9_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_7();
}


void test3_func_8_7( void )
{
  int i, x;
  int *p = &test3_array8[ 8 ][ 7 ];


  test3_func_8_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_7();
}


void test3_func_7_7( void )
{
  int i, x;
  int *p = &test3_array7[ 7 ][ 7 ];


  test3_func_7_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_7();
}


void test3_func_6_7( void )
{
  int i, x;
  int *p = &test3_array6[ 6 ][ 7 ];


  test3_func_6_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_7();
}


void test3_func_5_7( void )
{
  int i, x;
  int *p = &test3_array5[ 5 ][ 7 ];


  test3_func_5_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_7();
}


void test3_func_4_7( void )
{
  int i, x;
  int *p = &test3_array4[ 4 ][ 7 ];


  test3_func_4_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_7();
}


void test3_func_3_7( void )
{
  int i, x;
  int *p = &test3_array3[ 3 ][ 7 ];


  test3_func_3_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_7();
}


void test3_func_2_7( void )
{
  int i, x;
  int *p = &test3_array2[ 2 ][ 7 ];


  test3_func_2_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_7();
}


void test3_func_1_7( void )
{
  int i, x;
  int *p = &test3_array1[ 1 ][ 7 ];


  test3_func_1_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_7();
}


void test3_func_0_7( void )
{
  int i, x;
  int *p = &test3_array8[ 0 ][ 7 ];


  test3_func_0_8();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_7();
}


void test3_func_10_6( void )
{
  int i, x;
  int *p = &test3_array1[ 10 ][ 6 ];


  test3_func_10_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_6( void )
{
  int i, x;
  int *p = &test3_array8[ 9 ][ 6 ];


  test3_func_9_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_6();
}


void test3_func_8_6( void )
{
  int i, x;
  int *p = &test3_array7[ 8 ][ 6 ];


  test3_func_8_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_6();
}


void test3_func_7_6( void )
{
  int i, x;
  int *p = &test3_array6[ 7 ][ 6 ];


  test3_func_7_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_6();
}


void test3_func_6_6( void )
{
  int i, x;
  int *p = &test3_array5[ 6 ][ 6 ];


  test3_func_6_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_6();
}


void test3_func_5_6( void )
{
  int i, x;
  int *p = &test3_array4[ 5 ][ 6 ];


  test3_func_5_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_6();
}


void test3_func_4_6( void )
{
  int i, x;
  int *p = &test3_array3[ 4 ][ 6 ];


  test3_func_4_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_6();
}


void test3_func_3_6( void )
{
  int i, x;
  int *p = &test3_array2[ 3 ][ 6 ];


  test3_func_3_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_6();
}


void test3_func_2_6( void )
{
  int i, x;
  int *p = &test3_array1[ 2 ][ 6 ];


  test3_func_2_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_6();
}


void test3_func_1_6( void )
{
  int i, x;
  int *p = &test3_array8[ 1 ][ 6 ];


  test3_func_1_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_6();
}


void test3_func_0_6( void )
{
  int i, x;
  int *p = &test3_array7[ 0 ][ 6 ];


  test3_func_0_7();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_6();
}


void test3_func_10_5( void )
{
  int i, x;
  int *p = &test3_array8[ 10 ][ 5 ];


  test3_func_10_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_5( void )
{
  int i, x;
  int *p = &test3_array7[ 9 ][ 5 ];


  test3_func_9_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_5();
}


void test3_func_8_5( void )
{
  int i, x;
  int *p = &test3_array6[ 8 ][ 5 ];


  test3_func_8_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_5();
}


void test3_func_7_5( void )
{
  int i, x;
  int *p = &test3_array5[ 7 ][ 5 ];


  test3_func_7_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_5();
}


void test3_func_6_5( void )
{
  int i, x;
  int *p = &test3_array4[ 6 ][ 5 ];


  test3_func_6_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_5();
}


void test3_func_5_5( void )
{
  int i, x;
  int *p = &test3_array3[ 5 ][ 5 ];


  test3_func_5_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_5();
}


void test3_func_4_5( void )
{
  int i, x;
  int *p = &test3_array2[ 4 ][ 5 ];


  test3_func_4_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_5();
}


void test3_func_3_5( void )
{
  int i, x;
  int *p = &test3_array1[ 3 ][ 5 ];


  test3_func_3_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_5();
}


void test3_func_2_5( void )
{
  int i, x;
  int *p = &test3_array8[ 2 ][ 5 ];


  test3_func_2_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_5();
}


void test3_func_1_5( void )
{
  int i, x;
  int *p = &test3_array7[ 1 ][ 5 ];


  test3_func_1_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_5();
}


void test3_func_0_5( void )
{
  int i, x;
  int *p = &test3_array6[ 0 ][ 5 ];


  test3_func_0_6();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_5();
}


void test3_func_10_4( void )
{
  int i, x;
  int *p = &test3_array7[ 10 ][ 4 ];


  test3_func_10_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_4( void )
{
  int i, x;
  int *p = &test3_array6[ 9 ][ 4 ];


  test3_func_9_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_4();
}


void test3_func_8_4( void )
{
  int i, x;
  int *p = &test3_array5[ 8 ][ 4 ];


  test3_func_8_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_4();
}


void test3_func_7_4( void )
{
  int i, x;
  int *p = &test3_array4[ 7 ][ 4 ];


  test3_func_7_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_4();
}


void test3_func_6_4( void )
{
  int i, x;
  int *p = &test3_array3[ 6 ][ 4 ];


  test3_func_6_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_4();
}


void test3_func_5_4( void )
{
  int i, x;
  int *p = &test3_array2[ 5 ][ 4 ];


  test3_func_5_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_4();
}


void test3_func_4_4( void )
{
  int i, x;
  int *p = &test3_array1[ 4 ][ 4 ];


  test3_func_4_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_4();
}


void test3_func_3_4( void )
{
  int i, x;
  int *p = &test3_array8[ 3 ][ 4 ];


  test3_func_3_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_4();
}


void test3_func_2_4( void )
{
  int i, x;
  int *p = &test3_array7[ 2 ][ 4 ];


  test3_func_2_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_4();
}


void test3_func_1_4( void )
{
  int i, x;
  int *p = &test3_array6[ 1 ][ 4 ];


  test3_func_1_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_4();
}


void test3_func_0_4( void )
{
  int i, x;
  int *p = &test3_array5[ 0 ][ 4 ];


  test3_func_0_5();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_4();
}


void test3_func_10_3( void )
{
  int i, x;
  int *p = &test3_array6[ 10 ][ 3 ];


  test3_func_10_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_3( void )
{
  int i, x;
  int *p = &test3_array5[ 9 ][ 3 ];


  test3_func_9_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_3();
}


void test3_func_8_3( void )
{
  int i, x;
  int *p = &test3_array4[ 8 ][ 3 ];


  test3_func_8_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_3();
}


void test3_func_7_3( void )
{
  int i, x;
  int *p = &test3_array3[ 7 ][ 3 ];


  test3_func_7_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_3();
}


void test3_func_6_3( void )
{
  int i, x;
  int *p = &test3_array2[ 6 ][ 3 ];


  test3_func_6_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_3();
}


void test3_func_5_3( void )
{
  int i, x;
  int *p = &test3_array1[ 5 ][ 3 ];


  test3_func_5_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_3();
}


void test3_func_4_3( void )
{
  int i, x;
  int *p = &test3_array8[ 4 ][ 3 ];


  test3_func_4_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_3();
}


void test3_func_3_3( void )
{
  int i, x;
  int *p = &test3_array7[ 3 ][ 3 ];


  test3_func_3_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_3();
}


void test3_func_2_3( void )
{
  int i, x;
  int *p = &test3_array6[ 2 ][ 3 ];


  test3_func_2_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_3();
}


void test3_func_1_3( void )
{
  int i, x;
  int *p = &test3_array5[ 1 ][ 3 ];


  test3_func_1_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_3();
}


void test3_func_0_3( void )
{
  int i, x;
  int *p = &test3_array4[ 0 ][ 3 ];


  test3_func_0_4();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_3();
}


void test3_func_10_2( void )
{
  int i, x;
  int *p = &test3_array5[ 10 ][ 2 ];


  test3_func_10_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_2( void )
{
  int i, x;
  int *p = &test3_array4[ 9 ][ 2 ];


  test3_func_9_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_2();
}


void test3_func_8_2( void )
{
  int i, x;
  int *p = &test3_array3[ 8 ][ 2 ];


  test3_func_8_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_2();
}


void test3_func_7_2( void )
{
  int i, x;
  int *p = &test3_array2[ 7 ][ 2 ];


  test3_func_7_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_2();
}


void test3_func_6_2( void )
{
  int i, x;
  int *p = &test3_array1[ 6 ][ 2 ];


  test3_func_6_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_2();
}


void test3_func_5_2( void )
{
  int i, x;
  int *p = &test3_array8[ 5 ][ 2 ];


  test3_func_5_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_2();
}


void test3_func_4_2( void )
{
  int i, x;
  int *p = &test3_array7[ 4 ][ 2 ];


  test3_func_4_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_2();
}


void test3_func_3_2( void )
{
  int i, x;
  int *p = &test3_array6[ 3 ][ 2 ];


  test3_func_3_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_2();
}


void test3_func_2_2( void )
{
  int i, x;
  int *p = &test3_array5[ 2 ][ 2 ];


  test3_func_2_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_2();
}


void test3_func_1_2( void )
{
  int i, x;
  int *p = &test3_array4[ 1 ][ 2 ];


  test3_func_1_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_2();
}


void test3_func_0_2( void )
{
  int i, x;
  int *p = &test3_array3[ 0 ][ 2 ];


  test3_func_0_3();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_2();
}


void test3_func_10_1( void )
{
  int i, x;
  int *p = &test3_array4[ 10 ][ 1 ];


  test3_func_10_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_1( void )
{
  int i, x;
  int *p = &test3_array3[ 9 ][ 1 ];


  test3_func_9_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_1();
}


void test3_func_8_1( void )
{
  int i, x;
  int *p = &test3_array2[ 8 ][ 1 ];


  test3_func_8_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_1();
}


void test3_func_7_1( void )
{
  int i, x;
  int *p = &test3_array1[ 7 ][ 1 ];


  test3_func_7_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_1();
}


void test3_func_6_1( void )
{
  int i, x;
  int *p = &test3_array8[ 6 ][ 1 ];


  test3_func_6_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_1();
}


void test3_func_5_1( void )
{
  int i, x;
  int *p = &test3_array7[ 5 ][ 1 ];


  test3_func_5_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_1();
}


void test3_func_4_1( void )
{
  int i, x;
  int *p = &test3_array6[ 4 ][ 1 ];


  test3_func_4_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_1();
}


void test3_func_3_1( void )
{
  int i, x;
  int *p = &test3_array5[ 3 ][ 1 ];


  test3_func_3_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_1();
}


void test3_func_2_1( void )
{
  int i, x;
  int *p = &test3_array4[ 2 ][ 1 ];


  test3_func_2_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_1();
}


void test3_func_1_1( void )
{
  int i, x;
  int *p = &test3_array3[ 1 ][ 1 ];


  test3_func_1_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_1();
}


void test3_func_0_1( void )
{
  int i, x;
  int *p = &test3_array2[ 0 ][ 1 ];


  test3_func_0_2();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_1();
}


void test3_func_10_0( void )
{
  int i, x;
  int *p = &test3_array3[ 10 ][ 0 ];


  test3_func_10_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }
}


void test3_func_9_0( void )
{
  int i, x;
  int *p = &test3_array2[ 9 ][ 0 ];


  test3_func_9_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_10_0();
}


void test3_func_8_0( void )
{
  int i, x;
  int *p = &test3_array1[ 8 ][ 0 ];


  test3_func_8_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_9_0();
}


void test3_func_7_0( void )
{
  int i, x;
  int *p = &test3_array8[ 7 ][ 0 ];


  test3_func_7_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_8_0();
}


void test3_func_6_0( void )
{
  int i, x;
  int *p = &test3_array7[ 6 ][ 0 ];


  test3_func_6_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_7_0();
}


void test3_func_5_0( void )
{
  int i, x;
  int *p = &test3_array6[ 5 ][ 0 ];


  test3_func_5_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_6_0();
}


void test3_func_4_0( void )
{
  int i, x;
  int *p = &test3_array5[ 4 ][ 0 ];


  test3_func_4_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_5_0();
}


void test3_func_3_0( void )
{
  int i, x;
  int *p = &test3_array4[ 3 ][ 0 ];


  test3_func_3_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_4_0();
}


void test3_func_2_0( void )
{
  int i, x;
  int *p = &test3_array3[ 2 ][ 0 ];


  test3_func_2_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_3_0();
}


void test3_func_1_0( void )
{
  int i, x;
  int *p = &test3_array2[ 1 ][ 0 ];


  test3_func_1_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_2_0();
}


void test3_func_0_0( void )
{
  int i, x;
  int *p = &test3_array1[ 0 ][ 0 ];


  test3_func_0_1();

  _Pragma( "loopbound min 4 max 4" )
  for ( i = 0, x = 8; i < 4; i++, x >>= 1 ) {
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
    test3_result += *p;
    p += x;
  }

  test3_func_1_0();
}


/*
  Main functions
*/

void _Pragma ( "entrypoint" ) test3_main( void )
{
  test3_func_0_0();
}


// int main()
// {
//   struct timespec start, end;
//   long elapsed_ns;
//   double elapsed_us;

//   clock_gettime(CLOCK_MONOTONIC, &start);
//   test3_init();
//   test3_main();
//   clock_gettime(CLOCK_MONOTONIC, &end);

//   elapsed_ns = (end.tv_sec - start.tv_sec) * 1000000000L + (end.tv_nsec - start.tv_nsec);
//   elapsed_ns = (end.tv_sec - start.tv_sec) * 1000000000L + (end.tv_nsec - start.tv_nsec);

//   return ( test3_return() - 1377313800 != 0 );
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
    if (pthread_create(&thread, NULL, test3_thread, NULL) != 0) {
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
