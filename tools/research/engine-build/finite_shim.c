#define _GNU_SOURCE
#include <math.h>
/* glibc < 2.31 -ffast-math entry points used by the official static libs (built on Ubuntu 18.04) */
double __log_finite(double a){return log(a);}
float __logf_finite(float a){return logf(a);}
double __pow_finite(double a,double b){return pow(a,b);}
float __powf_finite(float a,float b){return powf(a,b);}
double __exp_finite(double a){return exp(a);}
float __expf_finite(float a){return expf(a);}
double __acos_finite(double a){return acos(a);}
float __acosf_finite(float a){return acosf(a);}
double __asin_finite(double a){return asin(a);}
float __asinf_finite(float a){return asinf(a);}
double __atan2_finite(double a,double b){return atan2(a,b);}
float __atan2f_finite(float a,float b){return atan2f(a,b);}
double __exp2_finite(double a){return exp2(a);}
float __exp2f_finite(float a){return exp2f(a);}
double __log10_finite(double a){return log10(a);}
float __log10f_finite(float a){return log10f(a);}
double __log2_finite(double a){return log2(a);}
float __log2f_finite(float a){return log2f(a);}
double __cosh_finite(double a){return cosh(a);}
float __coshf_finite(float a){return coshf(a);}
double __sinh_finite(double a){return sinh(a);}
float __sinhf_finite(float a){return sinhf(a);}
double __fmod_finite(double a,double b){return fmod(a,b);}
float __fmodf_finite(float a,float b){return fmodf(a,b);}
double __hypot_finite(double a,double b){return hypot(a,b);}
float __hypotf_finite(float a,float b){return hypotf(a,b);}
double __acosh_finite(double a){return acosh(a);}
float __acoshf_finite(float a){return acoshf(a);}
double __asinh_finite(double a){return asinh(a);}
float __asinhf_finite(float a){return asinhf(a);}
double __atanh_finite(double a){return atanh(a);}
float __atanhf_finite(float a){return atanhf(a);}
double __exp10_finite(double a){return exp10(a);}
float __exp10f_finite(float a){return exp10f(a);}
double __lgamma_finite(double a){return lgamma(a);}
float __lgammaf_finite(float a){return lgammaf(a);}
double __sqrt_finite(double a){return sqrt(a);}
float __sqrtf_finite(float a){return sqrtf(a);}
double __remainder_finite(double a,double b){return remainder(a,b);}
float __remainderf_finite(float a,float b){return remainderf(a,b);}
double __scalb_finite(double a,double b){return ldexp(a,(int)b);}
float __scalbf_finite(float a,float b){return ldexpf(a,(int)b);}
double __j0_finite(double a){return j0(a);}
float __j0f_finite(float a){return j0f(a);}
double __y0_finite(double a){return y0(a);}
float __y0f_finite(float a){return y0f(a);}

