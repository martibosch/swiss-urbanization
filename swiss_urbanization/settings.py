import os

from dotenv import find_dotenv, load_dotenv
from shapely import geometry

load_dotenv(find_dotenv())

EXTRACTS_URBAN = os.environ.get('EXTRACTS_URBAN', 1)
EXTRACTS_NONURBAN = os.environ.get('EXTRACTS_NONURBAN', 2)
EXTRACTS_NODATA = os.environ.get('EXTRACTS_NODATA', 0)

METRIC_LABEL_DICT = os.environ.get(
    'METRIC_LABEL_DICT', {
        'proportion_of_landscape': 'PLAND',
        'area_mn': 'MPS',
        'patch_density': 'PD',
        'edge_density': 'ED',
        'fractal_dimension_am': 'AWMFD',
        'euclidean_nearest_neighbor_mn': 'ENN',
        'contagion': 'CONTAG',
        'shannon_diversity_index': 'SHDI',
    })

# TODO: how to use `os.environ.get` for Python types other than string/numeric
# TODO: change hardcoded points and use overpass API filtering by tag
# `admin_centre:4=yes`
BASE_MASK_DICT = {
    'bern': geometry.Point(7.4514512, 46.9482713),
    'lausanne': geometry.Point(6.6327025, 46.5218269),
    'zurich': geometry.Point(8.5414061, 47.3769434)
}
BASE_MASK_CRS = 'epsg:4326'

MAX_BUFFER_DIST = os.environ.get('MAX_BUFFER_DIST', 20000)
BUFFER_DISTS = list(range(1000, 20000, 500))
