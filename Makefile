.PHONY: clean clean_raw clean_interim clean_processed download_data lint requirements sync_data_to_s3 sync_data_from_s3

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = ceat-spatiotemporal-patterns-switzerland
PROFILE = ceat
PROJECT_NAME = spatiotemporal-patterns-switzerland
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
DOWNLOAD_DATA_PY = swiss_urbanization/data/download_data.py

BOUNDARIES_DIR = data/raw/boundaries
BOUNDARIES_FILEPATH := $(BOUNDARIES_DIR)/ggg_2018-LV95/shp/g1a18.shp
CLC_YEAR_CODES = 00 06 12
CLC_DIR = data/raw/clc
CLC_DATASETS_DIRS := $(addprefix $(CLC_DIR)/, $(CLC_YEAR_CODES))

# rules
$(DOWNLOAD_DATA_PY): requirements
$(BOUNDARIES_FILEPATH): $(DOWNLOAD_DATA_PY)
	$(PYTHON_INTERPRETER) $(DOWNLOAD_DATA_PY) agglomeration-boundaries $(BOUNDARIES_DIR)
$(CLC_DIR):
	mkdir $(CLC_DIR)
$(CLC_DATASETS_DIRS): $(DOWNLOAD_DATA_PY) | $(CLC_DIR)
	$(PYTHON_INTERPRETER) swiss_urbanization/data/download_data.py clc-dataset $(notdir $@) $@
download_data: $(BOUNDARIES_FILEPATH) $(CLC_DATASETS_DIRS)

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

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete

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
