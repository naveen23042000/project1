pipeline {
    agent any
    environment {
        GITHUB_TOKEN = credentials('github-token')
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build') {
            steps {
                script {
                    // Get branch name with fallback for multibranch vs regular pipeline
                    def branchName = env.BRANCH_NAME ?: env.GIT_BRANCH?.replaceAll('origin/', '')
                    echo "Building for branch: ${branchName}"
                    
                    // Check Docker access
                    sh 'docker --version'
                    sh 'docker info'
                    
                    // Fix permission issue by making scripts executable
                    sh 'chmod +x build.sh'
                    sh './build.sh'
                }
            }
        }
        stage('Push to Docker Hub') {
            steps {
                script {
                    // Get branch name with fallback
                    def branchName = env.BRANCH_NAME ?: env.GIT_BRANCH?.replaceAll('origin/', '')
                    echo "Pushing Docker images for branch: ${branchName}"
                    // Use withCredentials for secure Docker login
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-hub-credentials',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )
                    ]) {
                        sh '''
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        '''
                        
                        // Push images based on branch
                        if (branchName == 'dev') {
                            sh '''
                                docker push $DOCKER_USER/dev:dev
                                docker push $DOCKER_USER/dev:latest
                            '''
                        } else if (branchName == 'main') {
                            sh '''
                                docker push $DOCKER_USER/prod:prod
                                docker push $DOCKER_USER/prod:latest
                            '''
                        } else {
                            echo "No Docker push configured for branch: ${branchName}"
                        }
                    }
                }
            }
        }
        stage('Deploy') {
            when {
                anyOf {
                    branch 'dev'
                    branch 'main' 
                    branch 'master'
                    // Add expression to handle cases where branch detection fails
                    expression { 
                        def branchName = env.BRANCH_NAME ?: env.GIT_BRANCH?.replaceAll('origin/', '')
                        return branchName == 'dev' || branchName == 'main' || branchName == 'master'
                    }
                    // Handle the HEAD case from your logs
                    expression {
                        return env.GIT_BRANCH?.contains('dev') || env.GIT_BRANCH?.contains('main')
                    }
                }
            }
            steps {
                script {
                    def branchName = env.BRANCH_NAME ?: env.GIT_BRANCH?.replaceAll('origin/', '')
                    echo "Deploying for branch: ${branchName}"
                    echo "Available environment variables:"
                    echo "BRANCH_NAME: ${env.BRANCH_NAME}"
                    echo "GIT_BRANCH: ${env.GIT_BRANCH}"
                    
                    // Fix permission issue for deploy script
                    sh 'chmod +x deploy.sh'
                    sh './deploy.sh'
                }
            }
        }
    }
    post {
        always {
            script {
                // Always logout from Docker Hub
                sh 'docker logout || true'
            }
        }
        success {
            echo 'Pipeline succeeded!'
        }
        failure {
            echo 'Pipeline failed!'
        }
        cleanup {
            // Clean up workspace if needed
            cleanWs()
        }
    }
}