import std.stdio;
import std.datetime;
import core.time;
import std.container;
import std.algorithm;
import std.range;
import std.random;
import std.math;

import gaussian;

enum NUMPHASEDOCKS 			= 2;		//number of phase docks available
enum PHASELENGTH 			= 7;		//number of work days a phase inspection takes
enum PHASEHOURS 			= 300;		//number of hours before a plane requires a phase inspection
enum PHASEWEEKENDS 			= true;	//true if phase inspections are active on weekends.
enum OPSCANXSPARE			= true;		//true if we can use ops cnx jets as a spare
enum WEEKENDLOCALS			= false;	//true if we are flying locals on weekends

enum MINCOMPLETEDURATION	= 0.0;		//can specify a minimum duration to be considered complete.

enum sparesPerGo 			= 2;		//desired number of spares per go.

//uses normal distribution
// normal(availability, availabilitySD)
enum availability 			= 0.8;		//mean percentage of jets on flight line that are flyable.
enum availabilitySD 		= 0.05;

enum gndAbortProb 			= 0.01;		//likelihood of ground abort with spare available		
enum airAbortProb 			= 0.01;		//likelihood of break w/ no spare. TODO: use historical data
enum incProb 				= 0.02;		//likelihood of ineffective sortie TODO: use historical data
										//TODO: increase likelihood of ineffective sortie if
										// duration is short.

//Simulated Sortie Durations
// Uses Skew Normal distribution
//NOTE: the numbers below produce a distribution that closely matches historical data 
enum asd 					= 2.0;		//2.1: ASD - will be decreased by a randomization factor.
enum asdSD 					= 0.5;		//0.5: standard deviation for sortie duration
enum asdSkew 				= -11.5;	//-18: Skew Normal distribution

//Simulated mx time to fix
// Uses normal distribution?
enum avgFixTime 			= 1.0;		//# of goes to fix problem TODO: use historical data
enum avgFixTimeVariance 	= 1.0;		//standard deviation for avg fix time 

enum weekendFixFactor 		= 5.0;		//scaling factor for avgFixTime if stuck off-station

enum wxProb 				= 0.05;		//likelihood of wx canceling a go TODO: use historical WX data
										//based on calendar year 
enum opsCancProb 			= 0.01;		//likelihood of an ops cancel TODO: use historical data,
										// and increase percentage based on IP availability

enum startYear				= 2018;
enum startMonth				= 2;
enum startDay				= 14;
enum daysToRun				= 90;

//Monthy weather attrition
// Set number of sorties canceled due to WX.
// Simulator currently cancels an entire go due to WX.
double[] wxAttritionByMonth = [0.196, 0.173, 0.164, 0.131, 0.104, 0.073, 0.103, 0.046, 0.117, 0.104, 0.112, 0.194];

int[4][] linesPerGoDay = [
							[20,20,20,0],
							[20,20,20,0],
							[20,20,20,0],
							[20,20,20,0],
							[20,20,20,0],
							[0,0,0,0],
							[0,0,0,0]];

//220 flying days per year currently
//TODO: take leap years into account.
//TODO: allow a pre-programmed flying calendar input
//int[365] flyScheduleDays = [];

enum {
	READY,
	WAITPHASE,
	INPHASE,
	BROKE
}

struct Tail
{
	string tailNumber;
	double totalHours = 0;	//TTAF, for now, just how many hours run during simulation
	double phaseHours;
	int phaseLeft = 0;		//how many days left in phase dock?
	int phaseWait = 0;		//how many days waiting on phase?
	int brokeWait = 0;		//how many goes waiting to get fixed?
							//TODO: use weekend launches for higher probability of
							// a longer fix.
	int status = READY;
}

Tail[] tails = [
	{tailNumber:"A6207", phaseHours:30.5},
	{tailNumber:"A3903", phaseHours:31.1},
	{tailNumber:"A3848", phaseHours:39.5},
	{tailNumber:"A3631", phaseHours:47.8},
	{tailNumber:"A3918", phaseHours:60.3},
	{tailNumber:"A3011", phaseHours:75.3},
	{tailNumber:"A3934", phaseHours:86.9},
	{tailNumber:"A3717", phaseHours:100.6},
	{tailNumber:"A3577", phaseHours:105.9},
	{tailNumber:"A3826", phaseHours:117.7},
	{tailNumber:"A3675", phaseHours:120.1},
	{tailNumber:"A3913", phaseHours:123.8},
	{tailNumber:"A3737", phaseHours:141.7},
	{tailNumber:"A6208", phaseHours:142.7},
	{tailNumber:"A3638", phaseHours:143.2},
	{tailNumber:"A3019", phaseHours:151.2},
	{tailNumber:"A3594", phaseHours:158.0},
	{tailNumber:"A3884", phaseHours:167.6},
	{tailNumber:"A6206", phaseHours:185.5},
	{tailNumber:"A3822", phaseHours:188.4},
	{tailNumber:"A3627", phaseHours:196.5},
	{tailNumber:"A3557", phaseHours:203.2},
	{tailNumber:"A6205", phaseHours:205.5},
	{tailNumber:"A3904", phaseHours:214.6},
	{tailNumber:"A3548", phaseHours:225.5},
	{tailNumber:"A3630", phaseHours:233.5},
	{tailNumber:"A3736", phaseHours:235.4},
	{tailNumber:"A3785", phaseHours:240.7},
	{tailNumber:"A3739", phaseHours:250.4},
	{tailNumber:"A3695", phaseHours:251.1},
	{tailNumber:"A3676", phaseHours:252.0},
	{tailNumber:"A3923", phaseHours:252.2},
	{tailNumber:"A3936", phaseHours:263.9},
	{tailNumber:"A6209", phaseHours:269.5},
	{tailNumber:"A3546", phaseHours:271.6},
	{tailNumber:"A3768", phaseHours:273.8},
	{tailNumber:"A3767", phaseHours:302.3},
	{tailNumber:"A3920", phaseHours:305.8},
	];

int num(Tail[] tails, int status)
{
	int ret = 0;
	foreach(t; tails)
	{
		if(t.status == status)
		{
			ret++;
		}
	}
	return ret;
}

size_t indexOfTailNumber(Tail[] ts, string tNum)
{
	foreach(idx, t; ts)
	{
		if(tNum == t.tailNumber)
		{
			return idx;
		}
	}
	throw(new Exception("tail number not found"));
}

//deliver a shuffled copy of the input array.
T[] shuffle(T)(T[] src)
{
	T[] output;
	output.length = src.length;

	for(int i = 0; i < src.length; i++)
	{
		int j = cast(int)uniform(0, i+1);

		if(j != i)
		{
			output[i] = output[j];
		}
		output[j] = src[i];
	}
	return output;
}

//return a copy of tails with a certain status
Tail[] getTailsWithStatus(Tail[] src, int status)
{
	Tail[] output;
	foreach(t; src)
	{
		if(t.status == status)
		{
			output ~= src;
		}
	}
	return output;
}

//Return a random number of goes that a plane will be broke.
int getBrokeWait(double ft = avgFixTime, double fv = avgFixTimeVariance)
{
	int fixTime = cast(int)round(normal(ft, fv));

	return max(1, fixTime);
}

bool isWeekday(Date d)
{
	if(d.dayOfWeek == DayOfWeek.sat || d.dayOfWeek == DayOfWeek.sun)
	{
		return false;
	}

	return true;
}

bool isWeekend(Date d)
{
	return !isWeekday(d);
}

double percentage(T : double)(T num, T den)
{
	return 100.0 * cast(double)num / cast(double)den;
}

string[] niceGo = ["1st","2nd","3rd","4th","5th"];
string[] niceDay = ["Sun", "Mon","Tue","Wed","Thu","Fri","Sat"];

void main()
{
	int numSims = 1;			//number of simulations to run (make this an argument)

	auto day = Date(startYear,startMonth,startDay);

	//RESULTS / OUTPUTS
	//int maxPhaseWaitSeen = 0;	//max length of time acft spends waiting for phase inspection 
	int maxInPhase = 0;			//max number of acft awaiting phase inspection during simulation

	int mndTot = 0;				//keep counter of when MX doesn't have enough tails to
								//support scheduled lines.

	int mxCanxTot = 0;			//number of mx cancels during simulation
	int wxCanxTot = 0;			//number of wx cancels during simulation
	int opsCanxTot = 0;			//number of ops cancels during simulation
	double hoursTot = 0;		//number of hours flown during simulation

	int scheduledTot = 0;		//number of sorties scheduled during simulation
	int sortiesTot = 0;			//number of sorties flown during simulation
	int effSortiesTot = 0;		//number of effective sorties during simulation
	int incSortiesTot = 0;		//number of ineffective sorties during simulation

	double longestSortie = 0;	//longest sortie done during simulation
	double shortestSortie = 3;	//shortest sortie flown during simulation

	//auto rng = Random(42);	//seed a random number generator
								//TODO: use randomize timer

	//TODO: add outer loop to allow simulation to be run many times
	//TODO: discover sensitivity to different variables

	//start flying year
	foreach(simulatedDay; 0..daysToRun)
	{
		//start flying day
		//see what our scheduled lines are
		int[4] linesPerGo;

		linesPerGo = linesPerGoDay[day.dayOfWeek].dup;

		//Once per day, see who is ready to leave the phase dock
		//first, make tails ready
		int dayPhaseTails = 0;						//number of acft awaiting phase today

		writeln("---------------------------------------------------------------------");
		writeln(niceDay[day.dayOfWeek], " ", day, " scheduled: ", linesPerGo, " expected WX attrition: ", 100*wxAttritionByMonth[day.month-1], "%");
		writeln("---------------------------------------------------------------------");

		foreach(ref t; tails)
		{
			//only take things out of phase if this is a weekday or if phase inspections
			// are occuring on weekends
			if(PHASEWEEKENDS == true || day.isWeekday)
			{
				if(t.status == INPHASE)
				{
					if(--t.phaseLeft <= 0)			//one day less in phase
					{
						writeln(t.tailNumber, " exiting phase.");
						t.status = READY;
						t.phaseHours = 0;			//reset phaseHours until next phase inspection
					}
					else
					{
						writeln(t.tailNumber, " has ", t.phaseLeft, " days remaining in dock.");
						dayPhaseTails++;
					}
				}
			}

			if(t.status == WAITPHASE)				//still waiting to get in the phase dock.
			{

				writeln(t.tailNumber, " has been waiting ", t.phaseWait, " days on a phase inspection.");
				t.phaseWait++;
				dayPhaseTails++;
			}

			if(dayPhaseTails > maxInPhase)
			{
				maxInPhase = dayPhaseTails;			//we have a new max number of tails waiting
													// on phase or in phase dock
			}
		}

		//put planes in phase if there's room
		//TODO: use bool above to see if we just freed anything up
		auto freeDocks = NUMPHASEDOCKS - tails.num(INPHASE);
		writeln(freeDocks, " free phase docks available.");

		//if we have free docks, see who gets them.
		foreach(dock; 0..freeDocks)
		{
			int highestWaitSeen = -1;
			int highestWaitSeenIndex = -1;

			//horribly inefficient, but shouldn't run too often
			foreach(index, ref t; tails)
			{
				if(t.status == WAITPHASE)
				{
					if(t.phaseWait > highestWaitSeen)
					{
						highestWaitSeen = t.phaseWait;
						highestWaitSeenIndex = cast(int)index;
					}
				}
			}

			//once we place a tail in phase inspection, we can start counting down
			// days left until inspection is complete.
			if(highestWaitSeen > -1 && highestWaitSeenIndex > -1)
			{
				writeln(tails[highestWaitSeenIndex].tailNumber, " entering phase");
				tails[highestWaitSeenIndex].status = INPHASE;
				tails[highestWaitSeenIndex].phaseLeft = PHASELENGTH;
				freeDocks--;
			}
		}

		//TODO: make this more efficient
		foreach(go, lines; linesPerGo)
		{
			scheduledTot += lines;

			//PER-GO Tail Updates for MX
			foreach(ref t; tails)
			{
				//assume phase over-flies are OK on weekends. TODO: verify this
				if(day.isWeekday && t.phaseHours > 300 && t.status == READY)
				{
					writeln(t.tailNumber, " awaiting phase");
					t.status = WAITPHASE;
					t.phaseWait = 0;
				}
				if(day.isWeekday && t.status == BROKE)
				{
					if(--t.brokeWait <= 0)			//another go closer to being fixed
					{
						t.status = READY;
					}
				}
			}

			//calculate probability of a WX canx.
			//TODO: take a look at the month and adjust wxProb accordingly.
			//TODO: consider reducing some percentage of lines based on WX.
			writeln("***");

			if(uniform01() <= wxAttritionByMonth[day.month-1])
			{
				wxCanxTot += lines;
				writeln(" ", niceGo[go], " go: canceled ", lines, " lines due to WX ");
			}
			else if(lines > 0)	//OK we're flying this go
			{
				//Determine MX losses
				writeln(" ", niceGo[go], " go: ", lines, " scheduled lines.");

				//reduce number of tails by availability rate
				auto numOnLine = tails.num(READY);
				auto mxReduction = normal(availability,availabilitySD);
				auto numFlyable = numOnLine * mxReduction;
				writeln(" MX Ready Rate: ", mxReduction, " num flyable: ", numFlyable);
				auto numReady = cast(int)round(fmin(numFlyable, numOnLine));

				//int tailsThisGo = ready.length - lines;
				writeln(" ", niceGo[go], " go: ", lines, " lines, ", numReady, " tails available of ", numOnLine, " tails on flight line.");

				foreach(ref r; tails)
				{
					if(r.status == READY)
					{
						write(" ", r.tailNumber[1..4]);
					}
				}
				writeln();

				//calculate MNDs and how many spares are available
				int numSparesThisGo = 0;

				if(numReady < lines)
				{
					auto mnd = lines - numReady;
					lines = numReady;					//we can only fly as many lines as we have tails
					writeln(" CAUTION: MX non-delivery of ", mnd, " tails.");
					mndTot += mnd;
					//assume no spares if numReady < lines
				}
				else
				{
					//Use no more than sparesPerGo spares this go.
					//numSparesThisGo = max(sparesPerGo, numReady - lines);
					int excessJets = numReady - lines;
					numSparesThisGo = min(sparesPerGo, excessJets);
				}


				//select tails to fly & spares, only 
				Tail[] tailsThisGo;
				int numTailsThisGo = lines + numSparesThisGo;
				tailsThisGo.length = numTailsThisGo;
				write(" Scheduling ",numTailsThisGo, " tails. ");

				//TODO: figure out weekend tails and XC
				tailsThisGo[0..numTailsThisGo] = shuffle(tails.getTailsWithStatus(READY))[0..numTailsThisGo];
	
				writeln(" Scheduled tails & spares this go: ");
				foreach(r; tailsThisGo)
				{
					write(" ", r.tailNumber[1..4]);
				}
				writeln();

				//numLines + spares.
				numTailsThisGo = cast(int)tailsThisGo.length;
				int linesFlownThisGo = 0;

				foreach(idx; 0..numTailsThisGo)
				{
					string thisTailNumber = tailsThisGo[idx].tailNumber;

					//put hours on the original list of tails.
					Tail *t = &tails[tails.indexOfTailNumber(thisTailNumber)];

					if(linesFlownThisGo == lines)
					{
						//flew our lines, don't need spares.
						break;
					}

					bool flyOpsCanxLine = false;

					//how many hours would we get if we flew?
					double sortieDuration = skewNormal(asd,asdSD,asdSkew);

					//keep some sanity here
					sortieDuration = min(sortieDuration,2.3);
					sortieDuration = max(sortieDuration,0.1);

					if(uniform01() <= opsCancProb)
					{
						opsCanxTot++;
						if(OPSCANXSPARE)
						{
							//ops canxed line turns into spare.
							// we can still use this tail.
							// TODO: make sure this only gets used as spare
							// and not flown.
							goto flyLine;
						}
					}
					else if(uniform01() <= gndAbortProb)
					{
						//plane is broke
						t.status = BROKE;
						//how long?
						t.brokeWait = getBrokeWait();

						//TODO: differentiate weekend locals vs weekend XCs
						if(day.isWeekday || WEEKENDLOCALS)
						{	
								//no spare, so it's a MX non-deliver
								mxCanxTot += 1;
								continue;	//try flying next tail
						}
					}
					else
					{
						flyLine:

						writef("%s flew %.1f", t.tailNumber, sortieDuration);

						//plane flies
						if(uniform01() <= incProb || sortieDuration < MINCOMPLETEDURATION)
						{
							//ineffective for some other reason (SNP, WX)
							incSortiesTot++;
							write(" ineffective");
						}
						else if(uniform01() <= airAbortProb)
						{
							//ineffective and jet breaks
							t.status = BROKE;
							t.brokeWait = getBrokeWait();

							incSortiesTot++;
							write(" early return, broken for ", t.brokeWait, " flying goes");
						}
						else
						{
							//effective
							effSortiesTot++;
							write(" effective");
						}
						
						//plane flies the sortie
						linesFlownThisGo++;
						
						//increase hours on this aircraft
						t.phaseHours += sortieDuration;
						t.totalHours += sortieDuration;

						//tally up simulation statistics
						hoursTot += sortieDuration;
						shortestSortie = fmin(shortestSortie, sortieDuration);
						longestSortie = fmax(longestSortie, sortieDuration);
						sortiesTot++;
						writeln();
					}
				}
			}
			else
			{
				//no lines scheduled this go.
				writeln(" No lines scheduled this go");
			}
		}

		day += days(1);
	}

	//calculate averages
	double avgASD = cast(double)hoursTot / cast(double)sortiesTot;
	double percentMND = percentage(mndTot, scheduledTot); //100.0 * cast(double)mndTot / cast(double)scheduledTot;
	double percentMXCanx = percentage(mxCanxTot, scheduledTot);
	double percentOpsCanx = percentage(opsCanxTot, scheduledTot);
	double percentWXCanx = percentage(wxCanxTot, scheduledTot);
	double percentEffOfScheduled = percentage(effSortiesTot, scheduledTot); //100.0 * cast(double)effSortiesTot / cast(double)scheduledTot;
	double percentIncomplete = percentage(incSortiesTot, sortiesTot); //100.0 * cast(double)incSortiesTot / cast(double)sortiesTot;
	//calculate warnings based on unrealistic sortie durations, etc.

	writeln();
	writeln(" Simulation Complete.");
	writeln("-----------------------------------------------");
	writeln(" Number of simulations:       ", numSims);
	writeln(" Days per simulation:         ", daysToRun);
	writeln(" Total lines scheduled:       ", scheduledTot);
	writeln(" Total MX non-deliveries:     ", mndTot);
	writefln("  %% MX non-delivered:          %.1f%%", percentMND);
	writeln(" Total MX cancels:            ", mxCanxTot);
	writefln("  %% MX canceled:               %.1f%%", percentMXCanx);
	writeln(" Total ops cancels:           ", opsCanxTot);
	writefln("  %% ops canceled:              %.1f%%", percentOpsCanx);
	writeln(" Total WX cancels:            ", wxCanxTot);
	writefln("  %% WX canceled:               %.1f%%", percentWXCanx);
	writeln(" Total sorties flown:.........", sortiesTot);
	writeln();
	writeln(" Total effective sorties:     ", effSortiesTot);
	writefln("  %% incomplete (of flown):    %.1f%%", percentIncomplete);
	writefln("  %% effective (of scheduled)  %.1f%%", percentEffOfScheduled);
	writeln();
	writeln(" Total incomplete sorties:    ", incSortiesTot);
	writeln();
	writefln(" Average sortie duration:     %.1f", avgASD);
	writefln(" Shortest sortie flown:       %.1f", shortestSortie);
	writefln(" Longest sortie flown:        %.1f", longestSortie);
	writeln();
	writeln(" Max # acft waiting on phase: ", maxInPhase);
	writeln(" Total hours flown:...........", hoursTot);
}