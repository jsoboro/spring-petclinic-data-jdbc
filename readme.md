# How to build 

* Build with gradlew

```
./gradlew build
```

* Docker Build and Docker Push with gradlew

```
./gradlew docker
./gradlew dockerPush
```

# How to run

* 본 과제는 Kubernetes cluster 및 MySQL DB(namespace: db)는 이미 구성되었다고 가정한다. 

```
# Service 와 Deployment 를 default 네임스페이스에 적용. 
$ kubectl apply -n default -f ./k8s/petclinic/petclinic-deployment.yaml

# Pod 생성 이후, Ingress 배포하여 기 생성된 Nginx Ingress Controller 와 연결하고 
# Ingress host 에 설정한 URL 로 접속한다. ( http://petclinic.35.103.3.40.nip.io )
$ kubectl apply -n default -f ./k8s/petclinic/petclinic-ingress.yaml
```

# 요구사항과 솔루션

* gradle을 사용하여 어플리케이션과 도커이미지를 빌드한다.
  * 상기 **How to build** 참조

* 어플리케이션의 log는 host의 /logs 디렉토리에 적재되도록 한다.
  * application.properties 내 logging.path 부분 추가
  * Deployment 내에 volumes 및 volumeMounts 추가 

```
### application.properties ###
logging.path=/logs
```
```
### k8s/petclinic/petclinic-deployment.yaml ###
        volumeMounts:
        - name: logs-volumes
          mountPath: /logs
      volumes:
        - name: logs-volumes
          emptyDir: {}
```

* 정상 동작 여부를 반환하는 api를 구현하며, 10초에 한번 체크하도록 한다. 3번 연속 체크에 실패하
면 어플리케이션은 restart 된다.
  * Deployment 내에 livenessProbe 추가, 이때 GET URL은 spring-boot-actuator 사용. 

```
### k8s/petclinic/petclinic-deployment.yaml ###
        livenessProbe:
          httpGet:
            path: /manage/health
            port: 8080
          failureThreshold: 3
          periodSeconds: 100
```

* 종료 시 30초 이내에 프로세스가 종료되지 않으면 SIGKILL로 강제 종료 시킨다.

```
### k8s/petclinic/petclinic-deployment.yaml ###
# default 값이 30 이나, 명시적으로 지정
      terminationGracePeriodSeconds: 30
```

* 배포 시와 scale in/out 시 유실되는 트래픽이 없어야 한다.
  * 무중단 배포를 위해 Application 단에는, Deployment Strategy 를 RollingUpdate 를 기본으로 하되, maxSurge: 1 / maxUnavailable: 0 를 설정. 
  * 또한 readinessProbe 에 대한 상세 요건은 없었기에 .spec.minReadySeconds 을 10초로 우선 설정. 
  * 상기 terminationGracePeriodSeconds 와 더불어 Graceful shutdown 기능 사용
    * 참고: https://docs.spring.io/spring-boot/docs/2.3.0.BUILD-SNAPSHOT/reference/html/spring-boot-features.html#boot-features-graceful-shutdown 

```
### k8s/petclinic/petclinic-deployment.yaml ###
  minReadySeconds: 10
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
    type: RollingUpdate
```
```
### application.properties ###
# Tomcat
server.shutdown=graceful

# To configure the timeout period
spring.lifecycle.timeout-per-shutdown-phase=30s 
```

* 어플리케이션 프로세스는 root 계정이 아닌 uid:1000으로 실행한다.

```
### Dockerfile ###
USER 1000
```

* DB도 kubernetes에서 실행하며 재 실행 시에도 변경된 데이터는 유실되지 않도록 설정한다.
  * Database 단에는, Statefulset 로 배포. 
  * mysql-statefulset.yaml 내용 참조

* 어플리케이션과 DB는 cluster domain을 이용하여 통신한다.
  * 참고로 mysql database 는 namespace: db 에 배포하였음. 

```
### application.properties ###
spring.datasource.url=jdbc:mysql://mysql.db.svc.cluster.local:3306/petclinic
```

* nginx-ingress-controller를 통해 어플리케이션에 접속이 가능하다.

```
# nginx-ingress-controller 는 기본 helm chart 통해서 아래 command 로 별도 설치 했다고 가정한다. 
$ helm install nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true
# 이때 nginx-ingress-controller 의 External IP 가 35.103.3.40 일 경우, ingress 자원으로 petclinic Service 와 연결해 주었으며, http://petclinic.35.103.3.40.nip.io 로 접속 가능. 
# ./k8s/petclinic/petclinic-ingress.yaml 참조
```

* namespace는 default를 사용한다.
  * manifest 상에 별도로 namespace 명시해 주지 않으면, default namespace 인 default 에 생성된다. 
  * 하지만 요구사항을 명확히 하기위해 namespace 에 default 명시하였음. 
  * k8s/petclinic/petclinic-deployment.yaml, k8s/petclinic/petclinic-ingress.yaml 참조. 
