import numpy as np

# Define a list of times and voltages, then produce a linear spline through it
from spline_dch_creation_coefficients import wvf_interpolate 
from spline_dch_creation_coefficients import spline_write 

# define the list of values in ms for the linear spline
total_time = 10.0
time_res = 0.02
time_list = np.arange(0, total_time+time_res, time_res)

# interpolate a function
final_val = 10;
time_factor = np.log(final_val)/total_time
amp_factor = 1;
# function for voltages
volt_list = (np.exp([x*time_factor for x in time_list]))
volt_list = np.multiply(amp_factor*volt_list, amp_factor)

# extract line durations and slops
spline_times,spline_volts,spline_derivs = wvf_interpolate(time_list, volt_list, 20)

file_handle = open('exp1.dat', 'w')
spline_write(spline_times,spline_volts,spline_derivs, 0, 'null', 0, 1, file_handle)
file_handle.close()
