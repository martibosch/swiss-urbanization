import pylandstats as pls


def get_landscapes_and_dates(ldf, nodata):
    """
    Auxiliary function to get the landscape rasters and dates of each
    agglomeration's land data frame
    """
    landscapes = []
    dates = []
    for urban_nonurban_column in ldf.columns[ldf.columns.str.startswith('AS')]:
        landscapes.append(
            pls.Landscape(ldf.to_ndarray(urban_nonurban_column, nodata=nodata),
                          res=ldf.res,
                          nodata=nodata))
        # get the year of the snapshot by taking the most recurrent timestamp
        # (year) among the pixels
        dates.append(ldf['FJ' +
                         urban_nonurban_column[2:4]].value_counts().index[0])
    return landscapes, dates
