import numpy as np


def urban_reclassify_clc(landscape_arr, urban_class, non_urban_class,
                         input_nodata, output_nodata):
    # function to reclassify CLC codes into urban/non-urban
    arr = np.copy(landscape_arr)
    arr[(arr >= 1) & (arr <= 11)] = urban_class
    arr[(arr != 1) & (arr != input_nodata)] = non_urban_class
    arr[arr == input_nodata] = output_nodata

    return arr
