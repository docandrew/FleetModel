module gaussian;

import std.math;
import std.stdio;
import std.random;

//Generate random numbers centered around 0 with a gaussian distribution
// use box-muller transform
double normal(double mu, double sigma)
{
	double u1, u2;
	double z0, z1;
	immutable double two_pi = 2.0*PI;

	do
	{
		u1 = uniform01();
 		u2 = uniform01();
	}while(u1 <= double.epsilon);

	z0 = (sqrt(-2.0 * log(u1)) * cos(two_pi * u2));
	z1 = (sqrt(-2.0 * log(u1)) * sin(two_pi * u2));

	return z0 * sigma + mu;
}

//create a skewed normal distribution
// NOTE: mu and sigma 
// From "A Method to Simulate the Skew Normal Distribution"
//  Ghorbanzadeh, Jaupi, Durand 17 Jun 2014
// Applied Mathematics, 2014, 5, 2073-2076
double skewNormal(double mu, double sigma, double skew)
{
	//get two normals in N(0,1)
	double u1 = normal(0,1);
	double u2 = normal(0,1);

	double u = fmax(u1,u2);
	double v = fmin(u1,u2);

	double thetaDenominator = sqrt(2.0*(1.0+(skew*skew)));
	double theta1 = (1.0+skew)/thetaDenominator;
	double theta2 = (1.0-skew)/thetaDenominator;

	double sn = (theta1 * u) + (theta2 * v);
	//sn is a "standardized" skew normal with mu=0, sigma=1,
	// now we apply desired mu & sigma values to our
	// "standardized" skew normal
	double ret = sn * sigma + mu;
	return ret;
}

//void main()
//{
//	foreach(i; 0..100)
//	{
//		writeln(skewNormal(2.0,0.5,-15));
//	}
//}