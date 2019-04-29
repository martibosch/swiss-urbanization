.PHONY: clean clean_raw clean_interim clean_processed clean_figures clean_py \
download_data agglomeration_extracts figures lint requirements sync_data_to_s3 \
sync_data_from_s3

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = ceat-swiss-urbanization
PROFILE = ceat
PROJECT_NAME = swiss-urbanization
PYTHON_INTERPRETER = python3
VIRTUALENV = conda

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## Install Python Dependencies
requirements: test_environment
ifeq (conda, $(VIRTUALENV))
	conda env update --name $(PROJECT_NAME) -f environment.yml
else
	$(PYTHON_INTERPRETER) -m pip install -U pip setuptools wheel
	$(PYTHON_INTERPRETER) -m pip install -r requirements.txt
endif

## Download data
# variables
# https://www.bfs.admin.ch/bfs/fr/home/services/geostat/geodonnees-statistique-federale/limites-administratives/limites-communales-generalisees.assetdetail.5247306.html
# https://www.bfs.admin.ch/bfs/fr/home/services/geostat/geodonnees-statistique-federale/sol-utilisation-couverture/statistique-suisse-superficie/nomenclature-standard.assetdetail.6646411.html
GMB_URI = https://www.bfs.admin.ch/bfsstatic/dam/assets/5247306/master
SLS_URI = https://www.bfs.admin.ch/bfsstatic/dam/assets/6646411/master
DOWNLOAD_FSO_PY = swiss_urbanization/data/download_fso.py

GMB_DIR = data/raw/gmb
GMB_SHP_BASENAME = g1a18
GMB_SHP_FILEPATH := $(GMB_DIR)/$(GMB_SHP_BASENAME).shp

SLS_DIR = data/raw/sls
SLS_CSV_FILEPATH := $(SLS_DIR)/AREA_NOAS04_17_181029.csv

# rules
$(GMB_DIR):
	mkdir $(GMB_DIR)
$(GMB_DIR)/%.zip: $(DOWNLOAD_FSO_PY) | $(GMB_DIR)
	$(PYTHON_INTERPRETER) $(DOWNLOAD_FSO_PY) $(GMB_URI) $@
$(GMB_DIR)/%.shp: $(GMB_DIR)/%.zip
	unzip -j $< 'ggg_2018-LV95/shp/$(GMB_SHP_BASENAME)*' -d $(GMB_DIR)
	touch $(GMB_SHP_FILEPATH)

$(SLS_DIR):
	mkdir $(SLS_DIR)
$(SLS_DIR)/%.zip: $(DOWNLOAD_FSO_PY) | $(SLS_DIR)
	$(PYTHON_INTERPRETER) $(DOWNLOAD_FSO_PY) $(SLS_URI) $@
$(SLS_DIR)/%.csv: $(SLS_DIR)/%.zip
	unzip -j $< '*.csv' -d $(SLS_DIR)
	touch $(SLS_CSV_FILEPATH)

download_gmb: $(GMB_SHP_FILEPATH)
download_sls: $(SLS_CSV_FILEPATH)


## AGGLOMERATION EXTRACTS
# variables
SETTINGS_PY = swiss_urbanization/data/settings.py

AGGLOMERATION_SLUGS = bern lausanne zurich
AGGLOMERATION_EXTRACTS_DIR = data/processed/agglomeration_extracts
MAKE_AGGLOMERATION_EXTRACT_PY = swiss_urbanization/data/make_agglomeration_extract.py

# rules
$(AGGLOMERATION_EXTRACTS_DIR):
	mkdir $(AGGLOMERATION_EXTRACTS_DIR)

$(MAKE_AGGLOMERATION_EXTRACT_PY): $(SETTINGS_PY)

$(AGGLOMERATION_EXTRACTS_DIR)/%.csv: $(SLS_CSV_FILEPATH) $(GMB_SHP_FILEPATH) $(MAKE_AGGLOMERATION_EXTRACT_PY) | $(AGGLOMERATION_EXTRACTS_DIR)
	$(PYTHON_INTERPRETER) $(MAKE_AGGLOMERATION_EXTRACT_PY) $(SLS_CSV_FILEPATH) $(GMB_SHP_FILEPATH) $(basename $(notdir $@)) $@

AGGLOMERATION_EXTRACTS_CSV_FILEPATHS := $(addprefix $(AGGLOMERATION_EXTRACTS_DIR)/, \
	$(foreach AGGLOMERATION_SLUG, $(AGGLOMERATION_SLUGS), $(AGGLOMERATION_SLUG).csv))

agglomeration_extracts: $(AGGLOMERATION_EXTRACTS_CSV_FILEPATHS)


## FIGURES
# variables
NOTEBOOKS_DIR = notebooks
FIGURES_DIR = reports/figures
FIGURE_BASENAMES = landscape_plots metrics_time_series growth_modes area_radius_scaling size_frequency_distribution population_change

# rules
# set larger timeout than default (some notebooks will need it)
$(FIGURES_DIR)/%.pdf: $(AGGLOMERATION_EXTRACTS_CSV_FILEPATHS)
	jupyter nbconvert --ExecutePreprocessor.timeout=600 --to notebook --execute $(NOTEBOOKS_DIR)/$(basename $(notdir $@)).ipynb 


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
	flake8 swiss_urbanization

## Upload Data to S3
sync_data_to_s3:
ifeq (default,$(PROFILE))
	aws s3 sync data/ s3://$(BUCKET)/data/
else
	aws s3 sync data/ s3://$(BUCKET)/data/ --profile $(PROFILE)
endif

## Download Data from S3
sync_data_from_s3:
ifeq (default,$(PROFILE))
	aws s3 sync s3://$(BUCKET)/data/ data/
else
	aws s3 sync s3://$(BUCKET)/data/ data/ --profile $(PROFILE)
endif

## Set up python interpreter environment
create_environment:
ifeq (conda,$(VIRTUALENV))
		@echo ">>> Detected conda, creating conda environment."
	conda env create --name $(PROJECT_NAME) -f environment.yml
		@echo ">>> New conda env created. Activate with:\nsource activate $(PROJECT_NAME)"
else
	$(PYTHON_INTERPRETER) -m pip install -q virtualenv virtualenvwrapper
	@echo ">>> Installing virtualenvwrapper if not already intalled.\nMake sure the following lines are in shell startup file\n\
	export WORKON_HOME=$$HOME/.virtualenvs\nexport PROJECT_HOME=$$HOME/Devel\nsource /usr/local/bin/virtualenvwrapper.sh\n"
	@bash -c "source `which virtualenvwrapper.sh`;mkvirtualenv $(PROJECT_NAME) --python=$(PYTHON_INTERPRETER)"
	@echo ">>> New virtualenv created. Activate with:\nworkon $(PROJECT_NAME)"
endif

## Test python environment is setup correctly
test_environment:
ifeq (conda,$(VIRTUALENV))
ifneq (${CONDA_DEFAULT_ENV}, $(PROJECT_NAME))
	$(error Must activate `$(PROJECT_NAME)` environment before proceeding)
endif
endif
	$(PYTHON_INTERPRETER) test_environment.py

#################################################################################
# PROJECT RULES                                                                 #
#################################################################################



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
