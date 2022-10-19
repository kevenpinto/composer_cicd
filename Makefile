# Include config File Vars
include config/env.config

COMPOSER_ENV?=${TF_VAR_dev_project}
SA_KEY=~/.config/gcloud/application_default_credentials.json
DAG_BUCKET?=$$(gcloud composer environments describe ${COMPOSER_ENV} --location ${TF_VAR_location}|grep dagGcsPrefix|cut -d ":" -f2-3)
PROJECT_NUMBER?=$$(gcloud projects list --filter=name=${TF_VAR_dev_project} --format="value(PROJECT_NUMBER)")
DEPLOYMENT_PROJECT_NUMBER?=$$(gcloud projects list --filter=name=${TF_VAR_deployment_project} --format="value(PROJECT_NUMBER)")
TF_VAR_tfstate_bucket ?= ${TF_VAR_deployment_project}-${DEPLOYMENT_PROJECT_NUMBER}-tfstate
BUILD_CONTAINER ?= cicd
BUILD_CONTAINER_TAG ?= latest
GCLOUD_DIR ?= $$(gcloud info --format='value(config.paths.global_config_dir)')
GCLOUD_MOUNT ?= -v $(GCLOUD_DIR):/root/.config/gcloud
ARTIFACT_REGISTRY_NAME=airflow-test-container
project_to_branch_map=$$(cat env_mapper.txt)
WORKDIR?=/workspace_stg

# Makefile command prefixes
continue_on_error = -
suppress_output = @

# Docker run options to prevent interactive mode running within pipelines.
run_options = -it

.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

.DEFAULT_GOAL := help

help: ## This is help
	$(suppress_output)awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test:
	@echo ${COMPOSER_ENV}

init: ## This will build the Local Dev Container
	$(suppress_output)gcloud components update
	$(suppress_output)docker build . -t ${BUILD_CONTAINER}:${BUILD_CONTAINER_TAG} -f cloudbuild/Dockerfile

bootstrap: auth## Creates a Deployment Project and Bucket to Store Terraform State -- Do this FIRST !! -- Also, Run this once only
	$(suppress_output)echo "Creating Deployment Project ${TF_VAR_deployment_project}"
	$(suppress_output)gcloud projects create ${TF_VAR_deployment_project} --folder=${TF_VAR_folder}
	$(suppress_output)gcloud beta billing projects link ${TF_VAR_deployment_project} --billing-account=${TF_VAR_billing_account}
	$(suppress_output)gcloud config set project ${TF_VAR_deployment_project}
	$(suppress_output)echo "Enabling Cloud Resource Manager API...."
	$(call run, gcloud services enable cloudresourcemanager.googleapis.com)
	$(suppress_output)echo "Enabling Artifact Registry API...."
	$(call run, gcloud services enable artifactregistry.googleapis.com)
	$(suppress_output)echo "Enabling Cloud Build API...."
	$(call run, gcloud services enable cloudbuild.googleapis.com)
	$(suppress_output)echo "Enabling Cloud Billing API...."
	$(call run, gcloud services enable cloudbilling.googleapis.com)
	$(call run, gcloud services enable container.googleapis.com)
	$(suppress_output)echo "Creating Terraform State Bucket ${TF_VAR_tfstate_bucket}...."
	$(call run, gsutil mb -c standard -l ${TF_VAR_location} -p ${TF_VAR_deployment_project} gs://${TF_VAR_tfstate_bucket})

repo: ## Setup Artifact Registry Docker Repo in the Deployment Project, Do this after bootstrap
	$(suppress_output)gcloud config set project ${TF_VAR_deployment_project}
	$(suppress_output)echo "Building Artifact Repo to Store Docker Image of Airflow Test Container...."
	$(suppress_output)gcloud artifacts repositories create ${ARTIFACT_REGISTRY_NAME} --repository-format=docker --location=${TF_VAR_location}

projects: ## Builds the Dev, Test and Prod Projects - Enable APIs and Setup Composer, Run this after make repo
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	apply \
	infra/projects \
 	${DEPLOYMENT_PROJECT_NUMBER})

composer: ## Sets up Composer 2 in your Projects
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	apply \
	infra/composer \
 	${DEPLOYMENT_PROJECT_NUMBER})

del-composer: ## Removes Composer 2 from your Projects
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	destroy \
	infra/composer \
 	${DEPLOYMENT_PROJECT_NUMBER})

triggers: ## Build CICD triggers against your GitHub Repo
	$(suppress_output)sed -i '' "s/TF_VAR_location/${TF_VAR_location}/g" $(PWD)/cloudbuild/pre-merge.yaml
	$(suppress_output)sed -i '' "s/TF_VAR_location/${TF_VAR_location}/g" $(PWD)/cloudbuild/on-merge.yaml
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	apply \
	infra/triggers \
	${DEPLOYMENT_PROJECT_NUMBER})

del-triggers: ## Destroy your Build Triggers
	$(suppress_output)sed -i '' "s/TF_VAR_location/${TF_VAR_location}/g" $(PWD)/cloudbuild/pre-merge.yaml
	$(suppress_output)sed -i '' "s/TF_VAR_location/${TF_VAR_location}/g" $(PWD)/cloudbuild/on-merge.yaml
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	destroy \
	infra/triggers \
	${DEPLOYMENT_PROJECT_NUMBER})

cleanup: del-composer ## NUCLEAR OPTION!! ---Drops the Bootstrap, Dev, Test and Prod Projects along with composer
	$(call run, bash /workspace_stg/infra/tf_utils.sh \
	destroy \
	infra/projects \
 	${DEPLOYMENT_PROJECT_NUMBER})
 	$(call run, gcloud projects delete ${DEPLOYMENT_PROJECT_NUMBER})

deploy: ## Deploy Dags to Your Dev Project -- This Runs your Unit tests first
	$(suppress_output)gcloud config set project ${TF_VAR_dev_project}
	$(suppress_output)echo ${DAG_BUCKET}
	$(call run, \
	  pytest ${WORKDIR}/tests \
	  && gsutil -m rsync -r dags/  ${DAG_BUCKET} \
	  && gsutil rm -rf ${DAG_BUCKET}/__pycache__* \
	  && gsutil rm -f ${DAG_BUCKET}/.DS_Store* \
	  && gsutil rm -f ${DAG_BUCKET}/*.pyc 
  )

tests: ## Run your Airflow Unit Tests -- Make sure you run `make init` at least once before running this
	$(call run, pytest ${WORKDIR}/tests)

shell: ##Gives Shell access to the container
	$(call run, /bin/bash)

auth: ##Google auth
	gcloud auth application-default login

checks: ## run pre-commit checks
	$(call run, pre-commit run --all-files)


# Mount Users gcloud creds on the Container
define run
	$(continue_on_error)docker run \
		--rm \
		${run_options} \
		-v $(PWD):${WORKDIR} \
		-v $(PWD)/config:/config:rw \
		-v $(SA_KEY):/credentials/access.json:ro \
		--env GOOGLE_APPLICATION_CREDENTIALS=/credentials/access.json \
		-e TF_VAR_tfstate_bucket=${TF_VAR_tfstate_bucket} \
		-e TF_VAR_deployment_project_number=${DEPLOYMENT_PROJECT_NUMBER} \
		--env-file ./config/env.config \
		${GCLOUD_MOUNT} \
		-w ${WORKDIR} \
		${BUILD_CONTAINER}:${BUILD_CONTAINER_TAG} \
		${1}
endef
