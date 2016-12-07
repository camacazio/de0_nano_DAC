## Import numpy
import numpy as np
import matplotlib.pyplot as plt
from scipy import interpolate

def wvf_interpolate(times, voltages, knot_frequency):
    """
    calculate b-spline interpolation derivatives for voltage data
    according to interpolation mode
    returns times, voltages and derivatives suitable for passing to
    serialize_branch()
    also removes the first time point (implicitly shifts to 0) and
    the last voltages/derivatives (irrelevant since the polynomial ends
    here) and sets the pause/trigger marker on the last point
    as desired by the fpga
    """

    ## For hfGUI purposes, I will only be using cubic splines
	## For DE0-Nano DAC purposes, I will only be using linear splines
    mode = 1

    derivatives = ()
    if mode in (1,2,3):
        ## Create a knot vector
        time_pts = times[::knot_frequency]
        voltage_pts = voltages[::knot_frequency]
        if time_pts[-1] != times[-1]:
            time_pts = np.append(time_pts, times[-1])
            voltage_pts = np.append(voltage_pts, voltages[-1])
            
        ## Create a spline through the voltage points at knot_frequency
        spline = interpolate.splrep(time_pts, voltage_pts, k = mode)
        derivatives = [interpolate.splev(time_pts, spline, der = i+1)
                        for i in range(mode)]

    ## In the case of just defining voltages, clear time_pts
    if mode == 0:
        time_pts = None
            
    # plot spline fit
    """
    Comment this plotting part out to speed up run-time
    """
    tnew = np.arange(times[1],times[-1],0.1)
    vnew = interpolate.splev(tnew,spline,der=0)
    plt.figure()
    plt.plot(times, voltages, 'r', tnew, vnew, 'b')
    plt.show()
    """
    """

    ## pass back all of the spline results
    return time_pts, voltage_pts, derivatives

def spline_write(times, voltages, derivatives, channel, wvf_name, branch, timeScale, file_handle):
    """
    This takes in the cubic spline data for a single channel.
    It then opens the target .dch file for the experiment,
    and writes/appends to the file
    """

    ## A constant electrode number offset
    #chan_start = 1
    #chan = channel + chan_start
    
    ## Make an h vector out of delta-t
    h = np.zeros(len(times)-1)
    for i in range(0,len(h)):
        h[i] = (times[i+1] - times[i])

    ## Use the derivatives matrix to produce a DC file that can be used
    ## Computed by matching t^n terms for the spline with that of the FPGA's
    ## discrete summed polynomial

    # file_handle.write('wvfcdef({0}_{1}, {2}, {3})\n'.format(wvf_name, chan, chan, branch))

    # # .dch spline data from spline derivatives
    # for i in range(0,len(h)):
        # file_handle.write('{0:.4f}\t{1:.4f}\t{2:.4f}\t{3:.4f}\t{4:.4f};\n'.format(
            # (times[i] + h[i])*timeScale, voltages[i],
            # h[i]*(derivatives[0][i]-derivatives[1][i]/2+derivatives[2][i]/6),
            # h[i]*(h[i]+1)*(derivatives[1][i]-derivatives[2][i])/2,
            # h[i]*(h[i]+1)*(h[i]+2)*derivatives[2][i]/6 ))
    
    # file_handle.write('wvfend\n\n')

    # .dch spline data from spline derivatives
    for i in range(0,len(h)):
        file_handle.write('{0:.4f} {1:.4f} {2:.4f}\n'.format(
            (times[i] + h[i])*timeScale, voltages[i],
            (voltages[i]+derivatives[0][i]*h[i])))
			
    ## Done writing this waveform channel
    return None
