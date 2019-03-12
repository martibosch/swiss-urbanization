import numpy as np

# ugly hardcoded mapping of pixel values (grid) and clc codes according to the
# `Legend/clc_legend.xls` file which can be found for the 90, 00, 06 and 12 CLC
# datasets. This could be better managed as we are hardcoding metadata.
# However reading it from a file would require the respective Makefile rules
# which turn things unnecessarily complicated.

grid_clc_dict = {
    1: 111,
    2: 112,
    3: 121,
    4: 122,
    5: 123,
    6: 124,
    7: 131,
    8: 132,
    9: 133,
    10: 141,
    11: 142,
    12: 211,
    13: 212,
    14: 213,
    15: 221,
    16: 222,
    17: 223,
    18: 231,
    19: 241,
    20: 242,
    21: 243,
    22: 244,
    23: 311,
    24: 312,
    25: 313,
    26: 321,
    27: 322,
    28: 323,
    29: 324,
    30: 331,
    31: 332,
    32: 333,
    33: 334,
    34: 335,
    35: 411,
    36: 412,
    37: 421,
    38: 422,
    39: 423,
    40: 511,
    41: 512,
    42: 521,
    43: 522,
    44: 523,
    48: 999,
    49: 990,
    50: 995,
    255: 990,
}


def urban_reclassify_clc(landscape_arr, urban_class, non_urban_class,
                         input_nodata, output_nodata):
    # function to reclassify CLC codes into urban/non-urban
    arr = np.copy(landscape_arr)

    if set(np.unique(arr)).issubset(set(grid_clc_dict)):
        # if the array codes correspond to the "grid" codes of CLC (the keys
        # of `grid_clc_dict`), we are dealing with the 00, 06 or 12 datasets
        arr[(arr >= 1) & (arr <= 11)] = urban_class
        arr[(arr != urban_class) & (arr != input_nodata)] = non_urban_class
        arr[arr == input_nodata] = output_nodata
    else:
        # here we assume that we are dealing with the 18 dataset, where the
        # pixel values directly correspond to the CLC codes (the values of
        # `grid_clc_dict`)
        # TODO: use `grid_clc_dict` to automatically get the extremes of each
        # interval, e.g., `grid_clc_dict[1]` instead of `111`
        arr[(arr >= 111) & (arr <= 142)] = urban_class
        arr[(arr != urban_class) & (arr != input_nodata)] = non_urban_class
        arr[arr == input_nodata] = output_nodata

    return arr
