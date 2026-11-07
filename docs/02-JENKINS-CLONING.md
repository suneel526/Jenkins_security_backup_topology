# Preserve and clone the existing Jenkins configuration

## What can be cloned, and what cannot be assumed

| Item | Recommended method | Important note |
|---|---|---|
| Controller configuration | JCasC export + reviewed YAML | Export is not a complete backup of all controller state. |
| Plugin inventory | Jenkins plugin manager API / `jenkins-plugin-cli --list` | Record exact versions from the running controller. Do not blindly upgrade. |
| Standard Pipeline job | Copy job to a new name or clone job config XML | Update only the new job's script path/parameters. |
| Multibranch Pipeline | Create a separate multibranch job with its own branch source/scan settings | Do not assume standard job-copy semantics cover branch indexing and credentials. |
| Freestyle job | Copy job config and inspect build steps/post-build actions | It may not be appropriate for a modern CD pipeline. |
| Credentials | Recreate credential IDs using approved secret sources | Do not export secrets to Git or plaintext files. |
| Build history/workspaces | Backup JENKINS_HOME/EBS if required | JCasC does not back up all build data. |
| Jenkins encryption keys | Protected JENKINS_HOME/EBS backup | Preserve `secrets/master.key` and `secrets/hudson.util.Secret`; protect them as secrets. |

## Export current configuration

The script `jenkins/export-existing-config.sh` expects:

```bash
export JENKINS_URL='https://jenkins.example.internal'
export JENKINS_USER='admin-or-read-only-admin'
export JENKINS_API_TOKEN='...'
./jenkins/export-existing-config.sh
```

The export is written under `jenkins-export/` (ignored by Git). Review for sensitive values before sharing or committing. The plugin inventory is a snapshot of the current controller; use it to build an explicit plugin lock file after compatibility testing.

JCasC endpoint depends on the Configuration as Code plugin being installed and enabled. If the endpoint is unavailable, install/upgrade the plugin only after backing up Jenkins and testing compatibility.

## Clone a standard job safely

```bash
export JENKINS_URL='https://jenkins.example.internal'
export JENKINS_USER='admin'
export JENKINS_API_TOKEN='...'
export SOURCE_JOB='payment-service-ci'
export TARGET_JOB='payment-service-cd'
./jenkins/clone-pipeline-job.sh
```

The script checks that the target does not already exist, verifies the source is a classic Pipeline job, creates a copy, and immediately disables the new copy to prevent inherited CI triggers from firing. It never updates or deletes the source job. After cloning:

1. Open the **new** `payment-service-cd` job.
2. Confirm SCM URL and branch.
3. Change its pipeline script path to `jenkins/Jenkinsfile.cd` (or the exact path used in your application repository).
4. Remove CI-only triggers/build steps from the **new** CD job if they are not appropriate.
5. Add `DEPLOY_ENV` and `IMAGE_DIGEST` parameters if not already present.
6. Configure the Jenkins folder/global variable `EKS_CLUSTER_NAME` using the Terraform output.
7. Verify credentials IDs and shared-library references without copying secret values.
8. Run a non-production test.

The helper deliberately refuses to clone Freestyle and Multibranch jobs. If the existing job is Multibranch Pipeline, use the Jenkins UI to create a second Multibranch Pipeline pointing to the same repository but with the CD script path. Do not run the standard clone script without understanding the source job type.

## JCasC application strategy

The starter `jenkins/casc/jenkins.yaml` is intentionally minimal. Do not replace the current controller configuration with it wholesale. Merge reviewed configuration into the exported configuration, validate it in a clone/test controller, and then apply using `CASC_JENKINS_CONFIG` or the JCasC UI reload endpoint according to your plugin version.

Keep secrets outside the YAML. Reference Jenkins credentials IDs, environment variables populated from a secret manager, or supported secret-source integrations. Never commit API tokens, passwords, private keys, or `credentials.xml`.

## Execution node

For an initial lab the CD Jenkinsfile uses `agent any`, but this may schedule deployment work on the controller. For production, create a dedicated trusted deployment agent/label with AWS CLI v2, kubectl, Helm, jq, restricted network access and no untrusted pull-request workloads. Change the `agent` directive only after that agent is available.
