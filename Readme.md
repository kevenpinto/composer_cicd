## A Demo Repo for [practicing CICD](https://medium.com/p/1ab2aaf53f99) in Google Cloud
- [Blog Part 1](https://medium.com/p/1ab2aaf53f99)
- [Blog Part 2](https://medium.com/p/2d0625ea44b0)


### Pre-Requisites
- Docker Desktop or Rancher Desktop installed on your Laptop/Dev Workstation
- gcloud configured
- A GCP user with permissions to create projects under Organisation/Folder
- git

####Step 1 --> Run `make init`
- This sets up a dev container on your machine

####Step 2 --> Run `make bootstrap`
- This will create the Bootstrap Project (Deployment Project).. This project will be the main command centre for all our CICD build and deploy activities
- This project will also act as our Project Factory for Spawning new projects and contain the Terraform State Bucket for these projects

####Step 3 --> Run `make repo`
- This command create a Docker Repo in Artifact Registry in the Deployment Project
- This Repo will contain our Test Airflow container that will Validate our DAGs

####Step 4 --> Run `make projects`
- This will setup the dev,test, prod projects

####Step 4.1 --> Run `make composer`
- This will install composer in the dev,test, prod projects

####Step 5 --> Run `make triggers`
- this will setup our CICD Triggers -- Make sure to connect Cloud Build to your Repo first

Type `make` to show help
```bash
help                           This is help
init                           This will build the Local Dev Container
bootstrap                      Creates a Deployment Project and Bucket to Store Terraform State -- Do this FIRST !! -- Also, Run this once only
repo                           Setup Artifact Registry Docker Repo in the Deployment Project, Do this after bootstrap
projects                       Builds the Dev, Test and Prod Projects - Enable APIs and Setup Composer, Run this after make repo
composer                       Sets up Composer 2 in your Projects
del-composer                   Removes Composer 2 from your Projects
triggers                       Build CICD triggers against your GitHub Repo
del-triggers                   Destroy your Build Triggers
cleanup                        NUCLEAR OPTION!! ---Drops the Bootstrap, Dev, Test and Prod Projects along with composer
deploy                         Deploy Dags to Your Dev Project -- This Runs your Unit tests first
tests                          Run your Airflow Unit Tests -- Make sure you run `make init` at least once before running this
checks                         run pre-commit checks

```

## Additional Reading
https://github.com/GoogleCloudPlatform/python-docs-samples/tree/main/composer/cicd_sample
https://cloud.google.com/composer/docs/dag-cicd-integration-guide
https://cloud.google.com/composer/docs/how-to/using/testing-dags
https://cloud.google.com/architecture/cicd-pipeline-for-data-processing
