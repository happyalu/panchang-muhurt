# Panchang and Muhurta

This repository contains code for an app that allows exploring the Vedic Panchanga, with tools to help select a good Muhurta. In particular, the tool allows either viewing the Panchanga for a given date, marked with potential red flags on timeslots, or using filters to search through a range of dates for good timeslots within which other aspects such as Lagna-Shuddhi can be done (outside of this tool).

# Motivation

I had taken a short course on [Panchanga and Muhurta](https://www.brhat.in/drashta/course/panchangam25) by Shri [Vedanjanam](https://x.com/VEDANJANAM)* ji.. To better understand some of the technical/mathematical concepts, I started implementing some of them here. With the help of feedback from others participating in the course, a more reasonable/usable tool took shape and is checked in here.

# Building

To build this from source, use the zig toolchain. (Tested with 0.14.1).

``` sh
zig build run
```

# License

The code in this repository is dual licensed: AGPL and MIT. This code currently depends on the swisseph library. If you are using swisseph as a build/runtime dependency, and do not have a professional license from the authors of swisseph, you must consider the AGPL license applicable to this codebase. 

If you modify this code to remove the dependency on swisseph (such as, by providing a different ephemeris backend), or if you own a professional license for swisseph, you have the choice between using AGPL or MIT for this codebase. 
