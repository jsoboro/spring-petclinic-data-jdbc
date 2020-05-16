FROM adoptopenjdk:8-jdk-hotspot
USER 1000
ARG JAR_FILE
COPY ${JAR_FILE} app.jar

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app.jar"]