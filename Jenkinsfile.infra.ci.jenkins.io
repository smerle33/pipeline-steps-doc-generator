#!/usr/bin/env groovy

pipeline {
    // This build requires at least 8Gb of memory
    agent { label 'linux-amd64-big' }
    triggers {
        cron('H H * * 0')
    }

    options {
        timestamps()
        timeout(time: 1, unit: 'HOURS')
    }

    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm
            }
        }

        stage('Prepare Indexer') {
            steps {
                dir('pluginFolder') {
                    git changelog: false,
                            poll: false,
                            url:'https://github.com/jenkinsci/backend-extension-indexer.git',
                        branch: 'master'
                    sh 'mvn -s ../settings.xml --no-transfer-progress clean install -DskipTests'
                }
            }
        }

        stage('Run Indexer') {
            steps {
                dir('pluginFolder') {
                    sh 'java -verbose:gc -XshowSettings:vm -jar ./target/*-bin/extension-indexer*.jar -plugins ./plugins && mv plugins ..'
                }
            }
        }

        stage('Generate Documentation') {
            steps {
                dir('docFolder') {
                    checkout scm
                    sh 'mvn -s ../settings.xml --no-transfer-progress clean install -DskipTests'
                    sh 'mv ../plugins . && java -verbose:gc -XshowSettings:vm -jar ./target/*-bin/pipeline-steps-doc-generator*.jar'
                }
            }
        }

        stage('Publish') {
            steps {
                dir('docFolder') {
                    // allAscii and declarative must not include directory name in their zip files
                    sh  '''
                        ( cd allAscii    && zip -r -1 -q ../allAscii.zip    . )
                        ( cd declarative && zip -r -1 -q ../declarative.zip . )
                        '''
                    script {
                        if (env.BRANCH_IS_PRIMARY) {
                            infra.publishReports(['allAscii.zip', 'declarative.zip'])
                        } else {
                            // On branches and PR, archive the files
                            archiveArtifacts artifacts: 'allAscii.zip,declarative.zip', fingerprint: true
                        }
                    }
                }
            }
        }
    }
}
