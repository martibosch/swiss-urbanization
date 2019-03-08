.PHONY: clean clean_raw clean_interim clean_processed clean_figures clean_py \
download_data swiss_extracts agglomeration_extracts municipal_extracts figure \
lint requirements sync_data_to_s3 sync_data_from_s3

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
DOWNLOAD_GMB_PY = swiss_urbanization/data/download_gmb.py
DOWNLOAD_CLC_PY = swiss_urbanization/data/download_clc.py

GMB_DIR = data/raw/gmb
GMB_SHP_BASENAME = g1a18
GMB_SHP_FILEPATH := $(GMB_DIR)/$(GMB_SHP_BASENAME).shp

CLC_DIR = data/raw/clc
CLC_YEAR_CODES = 00 06 12
CLC_TIF_FILEPATHS := $(foreach CLC_YEAR_CODE, $(CLC_YEAR_CODES), \
	$(CLC_DIR)/$(CLC_YEAR_CODE)/$(CLC_YEAR_CODE).tif)

# rules
# rules
$(GMB_DIR):
	mkdir $(GMB_DIR)
$(GMB_DIR)/%.zip: $(DOWNLOAD_GMB_PY) | $(GMB_DIR)
	$(PYTHON_INTERPRETER) $(DOWNLOAD_GMB_PY) $@
$(GMB_DIR)/%.shp: $(GMB_DIR)/%.zip
	unzip -j $< 'ggg_2018-LV95/shp/$(GMB_SHP_BASENAME)*' -d $(GMB_DIR)
	touch $(GMB_SHP_FILEPATH)

$(CLC_DIR):
	mkdir $(CLC_DIR)
$(CLC_DIR)/%.zip: $(DOWNLOAD_CLC_PY) | $(CLC_DIR)
	mkdir -p $(dir $@)
	$(PYTHON_INTERPRETER) $(DOWNLOAD_CLC_PY) $(basename $(notdir $@)) $@
$(CLC_DIR)/%.tif: $(CLC_DIR)/%.zip
	unzip $< -d $(dir $@)
	mv $(dir $@)*.tif $@
	if [ -f $(dir $@)*.aux ]; then mv $(dir $@)*.aux $(basename $@).aux; fi
	touch $@

download_gmb: $(GMB_SHP_FILEPATH)
download_clc: $(CLC_TIF_FILEPATHS)


## Swiss extracts
# variables
MAKE_SWISS_EXTRACT_PY = swiss_urbanization/data/make_swiss_extract.py
SWISS_EXTRACTS_DIR = data/interim/swiss_extracts
SWISS_EXTRACTS_TIF_FILEPATHS :=  $(foreach CLC_YEAR_CODE, $(CLC_YEAR_CODES), $(SWISS_EXTRACTS_DIR)/$(CLC_YEAR_CODE)/$(CLC_YEAR_CODE).tif)

# rules
$(SWISS_EXTRACTS_DIR):
	mkdir $(SWISS_EXTRACTS_DIR)
$(SWISS_EXTRACTS_DIR)/%.tif: $(CLC_DIR)/%.tif $(MAKE_SWISS_EXTRACT_PY) $(GMB_SHP_FILEPATH) | $(SWISS_EXTRACTS_DIR)
	mkdir -p $(dir $@)
	$(PYTHON_INTERPRETER) $(MAKE_SWISS_EXTRACT_PY) $(GMB_SHP_FILEPATH) $< $@
swiss_extracts: $(SWISS_EXTRACTS_TIF_FILEPATHS)

## URBAN EXTRACTS (MUNICIPAL + AGGLOMERATION)
# variables
UTILS_PY = swiss_urbanization/data/utils.py
SETTINGS_PY = swiss_urbanization/data/settings.py

CITY_SLUGS = basel bern geneve lausanne zurich
AGGLOMERATION_EXTRACTS_DIR = data/processed/agglomeration_extracts
MAKE_AGGLOMERATION_EXTRACT_PY = swiss_urbanization/data/make_agglomeration_extract.py

# rules
$(AGGLOMERATION_EXTRACTS_DIR):
	mkdir $(AGGLOMERATION_EXTRACTS_DIR)

$(MAKE_AGGLOMERATION_EXTRACT_PY): $(UTILS_PY) $(SETTINGS_PY)

define MAKE_AGGLOMERATION_EXTRACT
$(AGGLOMERATION_EXTRACTS_DIR)/$(CITY_SLUG)/%.tif: $(SWISS_EXTRACTS_DIR)/%.tif $(GMB_SHP_FILEPATH) $(MAKE_AGGLOMERATION_EXTRACT_PY) | $(AGGLOMERATION_EXTRACTS_DIR)
	mkdir -p $$(dir $$@)
	$(PYTHON_INTERPRETER) $(MAKE_AGGLOMERATION_EXTRACT_PY) $(GMB_SHP_FILEPATH) $(CITY_SLUG) $$< $$@
endef

AGGLOMERATION_EXTRACTS_TIF_FILEPATHS := $(addprefix $(AGGLOMERATION_EXTRACTS_DIR)/, \
	$(foreach CLC_YEAR_CODE, $(CLC_YEAR_CODES), \
		$(foreach CITY_SLUG, $(CITY_SLUGS), \
			$(CITY_SLUG)/$(CLC_YEAR_CODE)/$(CLC_YEAR_CODE).tif)))

agglomeration_extracts: $(AGGLOMERATION_EXTRACTS_TIF_FILEPATHS)

$(foreach CITY_SLUG, $(CITY_SLUGS), $(eval $(MAKE_AGGLOMERATION_EXTRACT)))

MUNICIPAL_EXTRACTS_DIR = data/processed/municipal_extracts
MAKE_MUNICIPAL_EXTRACT_PY = swiss_urbanization/data/make_municipal_extract.py
$(MUNICIPAL_EXTRACTS_DIR):
	mkdir $(MUNICIPAL_EXTRACTS_DIR)

$(MAKE_MUNICIPAL_EXTRACT_PY): $(UTILS_PY) $(SETTINGS_PY)

define MAKE_MUNICIPAL_EXTRACT
$(MUNICIPAL_EXTRACTS_DIR)/$(CITY_SLUG)/%.tif: $(SWISS_EXTRACTS_DIR)/%.tif $(GMB_SHP_FILEPATH) $(MAKE_MUNICIPAL_EXTRACT_PY) | $(MUNICIPAL_EXTRACTS_DIR)
	mkdir -p $$(dir $$@)
	$(PYTHON_INTERPRETER) $(MAKE_MUNICIPAL_EXTRACT_PY) $(GMB_SHP_FILEPATH) $(CITY_SLUG) $$< $$@
endef

MUNICIPAL_EXTRACTS_TIF_FILEPATHS := $(addprefix $(MUNICIPAL_EXTRACTS_DIR)/, \
	$(foreach CLC_YEAR_CODE, $(CLC_YEAR_CODES), \
		$(foreach CITY_SLUG, $(CITY_SLUGS), \
			$(CITY_SLUG)/$(CLC_YEAR_CODE)/$(CLC_YEAR_CODE).tif)))

municipal_extracts: $(MUNICIPAL_EXTRACTS_TIF_FILEPATHS)

$(foreach CITY_SLUG, $(CITY_SLUGS), $(eval $(MAKE_MUNICIPAL_EXTRACT)))


## Plot
# variables
VISUALIZE_PY = swiss_urbanization/visualization/visualize.py
FIGURE_FILEPATH = reports/figures/swiss-urbanization.png
METRICS = fractal_dimension_am edge_density

# rules
$(VISUALIZE_PY): # requirements
$(FIGURE_FILEPATH): $(VISUALIZE_PY) $(URBAN_EXTRACTS_FILEPATHS)
	$(PYTHON_INTERPRETER) $(VISUALIZE_PY) multi-city-plot $(URBAN_EXTRACTS_DIR) $(FIGURE_FILEPATH) --metrics $(METRICS) --year-codes $(CLC_YEAR_CODES) --city-slugs $(CITY_SLUGS)
figure: $(FIGURE_FILEPATH)

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
