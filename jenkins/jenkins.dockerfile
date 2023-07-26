FROM jenkins/jenkins:lts


COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
COPY kubectl /usr/share/jenkins/ref/kubectl


ENV KUBECONFIG ~/.kube
ENV JAVA_OPTS -Djenkins.install.runSetupWizard=false
ENV CASC_JENKINS_CONFIG /usr/share/jenkins/ref/casc.yaml
ENV PATH /usr/share/jenkins/ref:$PATH



RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt