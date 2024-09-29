pipeline {
    agent any

    tools {
        nodejs 'nodejs'
    }

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Choose which environment to deploy: Blue or Green')
        choice(name: 'DOCKER_TAG', choices: ['blue', 'green'], description: 'Choose the Docker image tag for the deployment')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue and Green')
    }

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        TAG = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = 'webapps'
        AWS_ACCOUNT_ID = credentials('ACCOUNT_ID')
        AWS_ECR_FRONTEND_REPO_NAME = credentials('ECR1')
        AWS_ECR_BACKEND_REPO_NAME = credentials('ECR2')
        AWS_DEFAULT_REGION = 'us-east-1'
        REPOSITORY_URI = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/"
        NVD_API_KEY = credentials('nvd-api-key')
    }

    stages {
        stage('Cleaning Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout from Git') {
            steps {
                git branch: 'main', credentialsId: 'GITHUB', url: 'https://github.com/gagnish/Blue-green-Devops-ArgoCD.git'
            }
        }

        stage('Code Analysis') {
            parallel {
                stage('Sonarqube Frontend Code Analysis') {
                    steps {
                        dir('Application-Code/frontend') {
                            withSonarQubeEnv('sonar-server') {
                                sh '''
                                $SCANNER_HOME/bin/sonar-scanner \
                                -Dsonar.projectName=frontend \
                                -Dsonar.projectKey=frontend
                                '''
                            }
                        }
                    }
                }

                stage('Sonarqube Backend Code Analysis') {
                    steps {
                        dir('Application-Code/backend') {
                            withSonarQubeEnv('sonar-server') {
                                sh '''
                                $SCANNER_HOME/bin/sonar-scanner \
                                -Dsonar.projectName=backend \
                                -Dsonar.projectKey=backend
                                '''
                            }
                        }
                    }
                }
            }
        }
   
        stage('Quality Check') {
            parallel {
                stage('Frontend Quality Check') {
                    steps {
                        script {
                            // Assuming frontend project is configured in SonarQube with a different project key
                            withSonarQubeEnv('sonar-server') { // Use your SonarQube server configuration here
                                waitForQualityGate abortPipeline: true, credentialsId: 'sonar-token'
                            }
                        }
                    }
                }
                stage('Backend Quality Check') {
                    steps {
                        script {
                            // Assuming backend project is configured in SonarQube with a different project key
                            withSonarQubeEnv('sonar-server') { // Use your SonarQube server configuration here
                                waitForQualityGate abortPipeline: true, credentialsId: 'sonar-token'
                            }
                        }
                    }
                }
            }
        }

        stage('Dependency Scans') {
            parallel {
                stage('OWASP Frontend Dependency-Check') {
                    steps {
                        dir('Application-Code/frontend') {
                            dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit --nvdApiKey ${NVD_API_KEY}', odcInstallation: 'DP-Check'
                            dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                        }
                    }
                }

                stage('OWASP Backend Dependency-Check') {
                    steps {
                        dir('Application-Code/backend') {
                            dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit --nvdApiKey ${NVD_API_KEY}', odcInstallation: 'DP-Check'
                            dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                        }
                    }
                }   
            }
        }

        stage('Trivy File Scans') {
            parallel {
                stage('Trivy Frontend File Scan') {
                    steps {
                        dir('Application-Code/frontend') {
                            sh 'trivy fs . >> trivyfs.txt'
                            script {
                                def scanResults = readFile('trivyfs.txt')
                                if (scanResults.contains('CRITICAL')) {
                                    echo "Warning: Critical vulnerabilities found in frontend file scan!"
                                }
                            }
                        }
                    }
                }

                stage('Trivy Backend File Scan') {
                    steps {
                        dir('Application-Code/backend') {
                            sh 'trivy fs . >> trivyfs.txt'
                            script {
                                def scanResults = readFile('trivyfs.txt')
                                if (scanResults.contains('CRITICAL')) {
                                    echo "Warning: Critical vulnerabilities found in backend file scan!"
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Build Tag and Push Docker Images') {
            parallel {
                stage("Build Tag and Push Frontend Docker Image") {
                    steps {
                        dir('Application-Code/frontend') {
                            // Conditional Docker pruning
                            sh '''
                                USED_DISK_SPACE=$(df / | tail -1 | awk \'{print $5}\' | sed \'s/%//\')
                                if [ $USED_DISK_SPACE -gt 80 ]; then
                                    echo "Disk space usage is above 80%, running docker system prune."
                                    docker system prune -f
                                    docker container prune -f
                                else
                                    echo "Disk space usage is below 80%, skipping prune."
                                fi
                            '''
                            sh 'docker build -t ${AWS_ECR_FRONTEND_REPO_NAME}:${TAG} .'
                            sh 'docker tag ${AWS_ECR_FRONTEND_REPO_NAME}:${TAG} ${REPOSITORY_URI}${AWS_ECR_FRONTEND_REPO_NAME}:${TAG}'
                            sh 'aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_URI}'
                            sh 'docker push ${REPOSITORY_URI}${AWS_ECR_FRONTEND_REPO_NAME}:${TAG}'
                        }
                    }
                }

                stage("Build Tag and Push Backend Docker Image") {
                    steps {
                        dir('Application-Code/backend') {
                            sh 'docker build -t ${AWS_ECR_BACKEND_REPO_NAME}:${TAG} .'
                            sh 'docker tag ${AWS_ECR_BACKEND_REPO_NAME}:${TAG} ${REPOSITORY_URI}${AWS_ECR_BACKEND_REPO_NAME}:${TAG}'
                            sh 'aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_URI}'
                            sh 'docker push ${REPOSITORY_URI}${AWS_ECR_BACKEND_REPO_NAME}:${TAG}'
                        }
                    }
                }
            }
        }

        stage("TRIVY Image Scan") {
            parallel {
                stage('Frontend Docker Image Scan') {
                    steps {
                        sh 'trivy image ${REPOSITORY_URI}${AWS_ECR_FRONTEND_REPO_NAME}:${TAG} >> trivyimage.txt'
                        script {
                            def scanResults = readFile('trivyimage.txt')
                            // Log the scan results without throwing an error
                            echo "Frontend scan results:\n${scanResults}"
                        }
                    }
                }

                stage('Backend Docker Image Scan') {
                    steps {
                        sh 'trivy image ${REPOSITORY_URI}${AWS_ECR_BACKEND_REPO_NAME}:${TAG} >> trivyimage.txt'
                        script {
                            def scanResults = readFile('trivyimage.txt')
                            // Log the scan results without throwing an error
                            echo "Backend scan results:\n${scanResults}"
                        }
                    }
                }
            }
        }
        
        stage('Deploy MongoDB and Service') {
            steps {
                dir('Kubernetes-Manifests-file') {
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', credentialsId: 'k8-cred', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6A9FF13EED6DDAC8D9624834D62E1FC2.gr7.us-east-1.eks.amazonaws.com') {
                        //sh "aws eks update-kubeconfig --name devopsshack-cluster --region us-east-1"
                        sh "kubectl apply -f Database -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }

        stage('Deploy Frontend & Backend Services') {
            steps {
                dir('Kubernetes-Manifests-file/Service') {
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', credentialsId: 'k8-cred', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6A9FF13EED6DDAC8D9624834D62E1FC2.gr7.us-east-1.eks.amazonaws.com') {
                        sh '''
                        kubectl apply -f backend-svc.yml --force -n ${KUBE_NAMESPACE}
                        kubectl apply -f frontend-svc.yml --force -n ${KUBE_NAMESPACE}
                        sleep 20
                        '''
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                dir('Kubernetes-Manifests-file/Deployment') {
                    script {
                        def deploymentFrontend = ""
                        def deploymentBackend = ""

                        if (params.DEPLOY_ENV == 'blue') {
                            deploymentFrontend = 'frontend-deployment-blue.yml'
                            deploymentBackend = 'backend-deployment-blue.yml'
                        } else {
                            deploymentFrontend = 'frontend-deployment-green.yml'
                            deploymentBackend = 'backend-deployment-green.yml' 
                        }

                        withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', credentialsId: 'k8-cred', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6A9FF13EED6DDAC8D9624834D62E1FC2.gr7.us-east-1.eks.amazonaws.com') {
                            sh "kubectl apply -f ${deploymentBackend} --record -n ${KUBE_NAMESPACE}"
                            sh "kubectl apply -f ${deploymentFrontend} --record -n ${KUBE_NAMESPACE}"
                            sh "sleep 20"
                        }
                    }
                }
            }
        }

        stage('Switch Traffic Between Blue & Green Environment') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                script {
                    def newEnv = params.DEPLOY_ENV

                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', credentialsId: 'k8-cred', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6A9FF13EED6DDAC8D9624834D62E1FC2.gr7.us-east-1.eks.amazonaws.com') {
                        sh """
                        kubectl patch svc backend-svc -p '{"spec": {"selector": {"app": "backend", "version": "${newEnv}"}}}' -n ${KUBE_NAMESPACE}
                        kubectl patch svc frontend-svc -p '{"spec": {"selector": {"app": "frontend", "version": "${newEnv}"}}}' -n ${KUBE_NAMESPACE}
                        """
                    }
                    echo "Traffic has been switched successfully to the ${newEnv} environment"
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    def verifyEnv = params.DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: ' devopsshack-cluster', contextName: '', credentialsId: 'k8-cred', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6A9FF13EED6DDAC8D9624834D62E1FC2.gr7.us-east-1.eks.amazonaws.com') {
                    sh "kubectl get pods -l version=${verifyEnv} -n ${KUBE_NAMESPACE}"
                    sh "kubectl get svc backend-svc -n ${KUBE_NAMESPACE}"
                    sh "kubectl get svc frontend-svc -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }
    }
}