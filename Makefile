.PHONY: clean clean_raw clean_interim clean_processed clean_figures clean_py \
	agglomeration_extracts breakpoints figures lint

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## GLOBALS
### variables
CODE_DIR = swiss_urbanization
DATA_DIR = data
DATA_RAW_DIR := $(DATA_DIR)/raw
DATA_PROCESSED_DIR := $(DATA_DIR)/processed

### rules
$(DATA_RAW_DIR): | $(DATA_DIR)
	mkdir $@
$(DATA_PROCESSED_DIR): | $(DATA_DIR)
	mkdir $@


## DOWNLOAD DATA
### variables
#### https://bit.ly/2thrc5V
GMB_URI = https://www.bfs.admin.ch/bfsstatic/dam/assets/5247306/master
#### https://bit.ly/2Nr5pQd
SLS_URI = https://www.bfs.admin.ch/bfsstatic/dam/assets/6646411/master
DOWNLOAD_URI_PY := $(CODE_DIR)/download_uri.py

GMB_DIR := $(DATA_RAW_DIR)/gmb
GMB_SHP_BASENAME = g1a18
GMB_SHP_FILEPATH := $(GMB_DIR)/$(GMB_SHP_BASENAME).shp

SLS_DIR := $(DATA_RAW_DIR)/sls
SLS_CSV_FILEPATH := $(SLS_DIR)/AREA_NOAS04_17_181029.csv

### rules
$(GMB_DIR): | $(DATA_RAW_DIR)
	mkdir $@
$(GMB_DIR)/%.zip: $(DOWNLOAD_URI_PY) | $(GMB_DIR)
	python $(DOWNLOAD_URI_PY) $(GMB_URI) $@
$(GMB_DIR)/%.shp: $(GMB_DIR)/%.zip
	unzip -j $< 'ggg_2018-LV95/shp/$(GMB_SHP_BASENAME)*' -d $(GMB_DIR)
	touch $@

$(SLS_DIR): | $(DATA_RAW_DIR)
	mkdir $(SLS_DIR)
$(SLS_DIR)/%.zip: $(DOWNLOAD_URI_PY) | $(SLS_DIR)
	python $(DOWNLOAD_URI_PY) $(SLS_URI) $@
$(SLS_DIR)/%.csv: $(SLS_DIR)/%.zip
	unzip -j $< '*.csv' -d $(SLS_DIR)
	touch $@

download_gmb: $(GMB_SHP_FILEPATH)
download_sls: $(SLS_CSV_FILEPATH)


## AGGLOMERATION EXTRACTS
### variables
SETTINGS_PY := $(CODE_DIR)/settings.py

AGGLOM_SLUGS = bern lausanne zurich
AGGLOM_EXTRACTS_DIR := $(DATA_PROCESSED_DIR)/agglom_extracts
MAKE_AGGLOM_EXTRACT_PY = $(CODE_DIR)/make_agglom_extract.py

AGGLOM_EXTRACTS_CSV_FILEPATHS := $(addprefix $(AGGLOM_EXTRACTS_DIR)/, \
	$(addsuffix .csv, $(AGGLOM_SLUGS)))

### rules
$(AGGLOM_EXTRACTS_DIR): | $(DATA_PROCESSED_DIR)
	mkdir $@

$(MAKE_AGGLOM_EXTRACT_PY): $(SETTINGS_PY)

$(AGGLOM_EXTRACTS_DIR)/%.csv: $(SLS_CSV_FILEPATH) $(GMB_SHP_FILEPATH) \
	$(MAKE_AGGLOM_EXTRACT_PY) | $(AGGLOM_EXTRACTS_DIR)
	python $(MAKE_AGGLOM_EXTRACT_PY) $(SLS_CSV_FILEPATH) \
		$(GMB_SHP_FILEPATH) $(basename $(notdir $@)) $@

agglomeration_extracts: $(AGGLOM_EXTRACTS_CSV_FILEPATHS)


## BREAKPOINTS (inner and outer zone in the area-radius scaling)
### variables
BREAKPOINTS_DIR := $(DATA_PROCESSED_DIR)/breakpoints

UTILS_PY := $(CODE_DIR)/utils.py
MAKE_BREAKPOINTS_PY := $(CODE_DIR)/make_breakpoints.py

BREAKPOINTS_JSON_FILEPATHS := $(addprefix $(BREAKPOINTS_DIR)/, \
	$(addsuffix .json, $(AGGLOM_SLUGS)))

### rules
$(BREAKPOINTS_DIR): | $(DATA_PROCESSED_DIR)
	mkdir $@

$(MAKE_BREAKPOINTS_PY): $(SETTINGS_PY) $(UTILS_PY)

$(BREAKPOINTS_DIR)/%.json: $(AGGLOM_EXTRACTS_DIR)/%.csv | $(BREAKPOINTS_DIR)
	python $(MAKE_BREAKPOINTS_PY) $< $@

breakpoints: $(BREAKPOINTS_JSON_FILEPATHS)


## FIGURES
### variables
FIGURES_DIR = reports/figures
FIGURE_BASENAMES = landscape_plots metrics_time_series growth_modes \
	area_radius_scaling size_frequency_distribution population_change

### rules
#### set larger timeout than default (some notebooks will need it)
$(FIGURES_DIR)/%.pdf: $(AGGLOM_EXTRACTS_CSV_FILEPATHS)
	jupyter nbconvert --ExecutePreprocessor.timeout=600 --to notebook \
		--execute $(NOTEBOOKS_DIR)/$(basename $(notdir $@)).ipynb 


FIGURES_PDF_FILEPATHS := $(addprefix $(FIGURES_DIR)/, \
	$(foreach FIGURE_BASENAME, $(FIGURE_BASENAMES), $(FIGURE_BASENAME).pdf))

figures: $(FIGURES_PDF_FILEPATHS)


## Clean Datasets
clean_raw:
	find data/raw/ ! -name '.gitkeep' -type f -exec rm -f {} +
	find data/raw/ ! -path data/raw/ -type d -exec rm -rf {} +

clean_interim:
	find data/interim/ ! -name '.gitkeep' -type f -exec rm -f {} +
	find data/interim/ ! -path data/interim/ -type d -exec rm -rf {} +

clean_processed:
	find data/processed/ ! -name '.gitkeep' -type f -exec rm -f {} +
	find data/processed/ ! -path data/processed/ -type d -exec rm -rf {} +

## Clean Figures
clean_figures:
	find reports/figures/ ! -name '.gitkeep' -type f -exec rm -f {} +
	find reports/figures/ ! -path reports/figures/ -type d -exec rm -rf {} +
	rm notebooks/*.nbconvert.ipynb

## Delete all compiled Python files
clean_py:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete

## Clean all (except raw)
clean: clean_interim clean_processed clean_figures clean_py

## Lint using flake8
lint:
	flake8 $(CODE_DIR)


#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
