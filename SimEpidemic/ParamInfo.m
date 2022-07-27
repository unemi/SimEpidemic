//
//  ParamInfo.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/07/13.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "Sources/CommonTypes.h"
#import "ParamInfo.h"

ParamInfo paramInfo[] = {
	{ ParamTypeFloat, @"mass", {.f = { 20., 1., 100.}}},
	{ ParamTypeFloat, @"friction", {.f = { 80., 0., 100.}}},
	{ ParamTypeFloat, @"avoidance", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"maxSpeed", {.f = { 50., 10., 100.}}},

	{ ParamTypeFloat, @"activenessMode", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"activenessKurtosis", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"massBias", {.f = { 4., 1., 10.}}},
	{ ParamTypeFloat, @"mobilityBias", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringBias", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"incubationBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"fatalityBias", {.f = { 0., -100., 100.}}},
//	{ ParamTypeFloat, @"recoveryBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"immunityBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"therapyEfficacy", {.f = { 0., 0., 100.}}},

	{ ParamTypeFloat, @"contagionDelay", {.f = { .5, 0., 10.}}},
	{ ParamTypeFloat, @"contagionPeak", {.f = { 3., 1., 10.}}},
	{ ParamTypeFloat, @"infectionProberbility", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"infectionDistance", {.f = { 3., .1, 10.}}},

	{ ParamTypeFloat, @"distancingStrength", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"distancingObedience", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"backHomeRate", {.f = { 75., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringFrequency", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringSpotRandom", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringActiveBias", {.f = { 0., 0., 100.}}},
	{ ParamTypeFloat, @"contactTracing", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"testDelay", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testProcess", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testInterval", {.f = { 2., 0., 10.}}},
	{ ParamTypeFloat, @"testSensitivity", {.f = { 70., 0., 100.}}},
	{ ParamTypeFloat, @"testSpecificity", {.f = { 99.8, 0., 100.}}},
	{ ParamTypeFloat, @"subjectAsymptomatic", {.f = { 1., 0., 100.}}},
	{ ParamTypeFloat, @"subjectSymptomatic", {.f = { 99., 0., 100.}}},
	{ ParamTypeFloat, @"testCapacity", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"testDelayLimit", {.f = { 3., 1., 14.}}},
	{ ParamTypeFloat, @"immuneMaxPeriod", {.f = { 200., 50., 500.}}},
	{ ParamTypeFloat, @"immuneMaxPrdSeverity", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"immuneMaxEfficacy", {.f = { 90., 0., 100.}}},
	{ ParamTypeFloat, @"immuneMaxEffcSeverity", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"immunityDecay", {.f = { 60., 0., 100.}}},

	{ ParamTypeDist, @"mobilityDistance", {.d = { 10., 30., 80.}}},
	{ ParamTypeDist, @"incubation", {.d = { 1., 5., 14.}}},
	{ ParamTypeDist, @"fatality", {.d = { 4., 16., 20.}}},
//	{ ParamTypeDist, @"recovery", {.d = { 4., 10., 40.}}},
//	{ ParamTypeDist, @"immunity", {.d = { 30., 180., 360.}}},
	{ ParamTypeDist, @"gatheringSize", {.d = { 5., 10., 20.}}},
	{ ParamTypeDist, @"gatheringDuration", {.d = { 6., 12., 24.}}},
	{ ParamTypeDist, @"gatheringStrength", {.d = { 50., 80., 100.}}},
	{ ParamTypeDist, @"mobilityFrequency", {.d = { 40., 70., 100.}}},
	{ ParamTypeDist, @"gatheringParticipation", {.d = { 40., 70., 100.}}},
	
	{ ParamTypeInteger, @"populationSize", {.i = { 10000, 100, 999900}}},
	{ ParamTypeInteger, @"worldSize", {.i = { 360, 10, 999999}}},
	{ ParamTypeInteger, @"mesh", {.i = { 18, 1, 999}}},
//	{ ParamTypeInteger, @"initialInfected", {.i = { 20, 1, 999}}},
	{ ParamTypeInteger, @"stepsPerDay", {.i = { 12, 1, 999}}},
	
	{ ParamTypeRate, @"initialInfectedRate", {.f = { .1, 0., 100.}}},
	{ ParamTypeRate, @"initialRecovered", {.f = { 0., 0., 100.}}},
	{ ParamTypeRate, @"quarantineAsymptomatic", {.f = { 20., 0., 100.}}},
	{ ParamTypeRate, @"quarantineSymptomatic", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"popDistMapLog2Gamma", {.f = { 0., -3., 3.}}},
	{ ParamTypeRate, @"gatheringSpotFixed", {.f = { 0., 0., 100.}}},
//	{ ParamTypeRate, @"vaccineAntiRate", {.f = { 30., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxClusterRate", {.f = { 60., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxClusterGranularity", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxTestRate", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"recoveryBias", {.f = { 150., 0., 200.}}},
	{ ParamTypeRate, @"recoveryTemp", {.f = { 50., 1., 100.}}},
	{ ParamTypeRate, @"recoveryUpperRate", {.f = { 500., 100., 900.}}},
	{ ParamTypeRate, @"recoveryLowerRate", {.f = { 40., 0., 100.}}},
	{ ParamTypeRate, @"vaccineFirstDoseEfficacy", {.f = { 30., 0., 100.}}},
	{ ParamTypeRate, @"vaccineMaxEfficacy", {.f = { 90., 0., 100.}}},
	{ ParamTypeRate, @"vaccineEfficacySymp", {.f = { 95., 0., 100.}}},
	{ ParamTypeRate, @"vaccineEffectDelay", {.f = { 14., 0., 30.}}},
	{ ParamTypeRate, @"vaccineEffectPeriod", {.f = { 7., 0., 60.}}},
	{ ParamTypeRate, @"vaccineEffectDecay", {.f = { 120., 0., 500.}}},
	{ ParamTypeRate, @"vaccineSvEfficacy", {.f = { 90., 0., 99.}}},
	{ ParamTypeRate, @"infectionDistanceBias", {.f = { 0.9, 0., 5.}}},
	{ ParamTypeRate, @"contagionBias", {.f = { 33., 0., 200.}}},

	{ ParamTypeEnum, @"tracingOperation", {.e = {0, 2}}},
	{ ParamTypeEnum, @"vaccineTypeForTracingVaccination", {.e = {0, MAX_N_VAXEN - 1}}},
	{ ParamTypeWEnum, @"workPlaceMode", {.e = {0, 3}}},
	{ ParamTypeBoolean, @"familyModeOn", {.b = {NO}}},
	{ ParamTypeTimeInterval, @"startTime", {.f = { 33., 0., 200.}}},

	{ ParamTypeNone, nil }
};

