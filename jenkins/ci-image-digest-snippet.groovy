// OPTIONAL snippet for the existing CI pipeline after it successfully pushes an immutable image tag.
// Do not replace or modify your working CI Jenkinsfile until its current behavior has been backed up and tested.
// Set IMAGE_TAG to a unique commit/build tag that is never reused in the immutable ECR repository.
stage('Publish immutable image digest') {
    steps {
        script {
            def digest = sh(
                script: "aws ecr describe-images --repository-name payment-service --image-ids imageTag=${IMAGE_TAG} --region ap-south-2 --query 'imageDetails[0].imageDigest' --output text",
                returnStdout: true
            ).trim()
            if (!(digest ==~ /^sha256:[0-9a-f]{64}$/)) {
                error("Could not resolve an immutable ECR image digest: ${digest}")
            }
            writeFile file: 'image-digest.txt', text: digest + '\n'
            archiveArtifacts artifacts: 'image-digest.txt', fingerprint: true
            // Optional downstream trigger after you configure payment-service-cd:
            // build job: 'payment-service-cd', parameters: [
            //   string(name: 'DEPLOY_ENV', value: 'dev'),
            //   string(name: 'IMAGE_DIGEST', value: digest)
            // ], wait: false
        }
    }
}
