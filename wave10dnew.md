# EOS Quark Core Parity — Wave 10D Copy Packet

Revision: single-main-`application.yaml` version, 2026-08-26.

Apply every serial in order after Wave 10C. The deployment-time environment/profile/secret configuration split is
explicitly deferred at the user's request.

Important boundaries:

- Keep the repository's existing single `src/main/resources/application.yaml`; do not replace it wholesale.
- Do not create or copy `application-local.yaml`, `application-env.yaml`, `application-secrets.yml`, or a revised
  `application-test.yaml` from this wave.
- Keep all current datasource, Rabbit connection, QXPS and QXPSM endpoint/credential values unchanged.
- Rabbit input remains disabled during REST verification with `engine.input.rabbit.enabled: false`.
- Do not delete or recopy the 276 committed Axis generated classes; this packet stops normal builds from rewriting them.
- Do not edit `Jenkinsfile` or `.gitignore` from this packet.
- Externalizing and rotating committed credentials remains a mandatory deployment gate, but it is not part of this
  transfer packet.
- The removal of `fetchActiveRunIds()` is already present in Wave 10C serials 2, 3 and 8, so those files are not
  duplicated here.

## 1. `pom.xml`

SHA-256: `d4face2bcb850cc07fd01678c7fecb14dfe6a7516c0da71449576e8e02a6954f`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xmlns="http://maven.apache.org/POM/4.0.0"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>com.socgen.sgs.sgs-stack</groupId>
    <artifactId>sgs-api-core</artifactId>
    <version>11.5.1</version>
    <relativePath />
  </parent>

  <groupId>com.socgen.sgs.api</groupId>
  <artifactId>quark-engine-service</artifactId>
  <version>1.0.0-SNAPSHOT</version>

  <name>quark-batch-job REST API</name>
  <description>REST API to manage quark data</description>

  <!--    <properties>-->
  <!--&lt;!&ndash;        <sonar.projectKey>PUT YOUR SONAR KEY HERE</sonar.projectKey>&ndash;&gt;-->
  <!--    </properties>-->

  <properties>
    <lombok.version>1.18.30</lombok.version>
  </properties>

  <dependencies>
    <!-- Spring Boot Starters -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <!-- ⇓ BEGIN database dependencies ⇓ -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>

    <dependency>
      <groupId>org.liquibase</groupId>
      <artifactId>liquibase-core</artifactId>
    </dependency>

    <!-- H2 Database - for local development and testing -->
    <dependency>
      <groupId>com.h2database</groupId>
      <artifactId>h2</artifactId>
      <scope>runtime</scope>
    </dependency>

    <!-- PostgreSQL -->
    <!--        <dependency>-->
    <!--            <groupId>org.postgresql</groupId>-->
    <!--            <artifactId>postgresql</artifactId>-->
    <!--        </dependency>-->

    <!-- Oracle (defaults to ojdbc10)-->
    <dependency>
      <groupId>com.oracle.database.jdbc</groupId>
      <artifactId>${com.oracle-ojdbc-artifactId}</artifactId>
    </dependency>
    <!-- ⇑ END database dependencies ⇑ -->

    <!-- AMQP/RabbitMQ -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-amqp</artifactId>
    </dependency>


    <!-- API Bank dependencies -->
    <dependency>
      <groupId>com.socgen.apibank</groupId>
      <artifactId>apibank-starter-openapi</artifactId>
    </dependency>

    <dependency>
      <groupId>com.socgen.apibank</groupId>
      <artifactId>http-rate-limiter</artifactId>
    </dependency>

    <dependency>
      <groupId>com.socgen.apibank</groupId>
      <artifactId>security-sgconnect-mock</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>com.socgen.apibank</groupId>
      <artifactId>apibank-starter-security-client</artifactId>
    </dependency>

    <!-- Security -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-security</artifactId>
    </dependency>

    <!-- WebFlux -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webflux</artifactId>
    </dependency>

    <!-- SocGen utilities -->
    <dependency>
      <groupId>com.socgen.sgs.util</groupId>
      <artifactId>java-functional</artifactId>
    </dependency>

    <!-- Mapping between Java objects -->
    <dependency>
      <groupId>org.mapstruct</groupId>
      <artifactId>mapstruct</artifactId>
    </dependency>

    <!-- Problem Spring Web -->
    <dependency>
      <groupId>org.zalando</groupId>
      <artifactId>problem-spring-web</artifactId>
      <version>0.29.1</version>
    </dependency>

    <!-- AWS SDK -->
    <dependency>
      <groupId>com.amazonaws</groupId>
      <artifactId>aws-java-sdk</artifactId>
      <version>1.12.519</version>
    </dependency>

    <!-- Commons IO -->
    <dependency>
      <groupId>commons-io</groupId>
      <artifactId>commons-io</artifactId>
      <version>2.13.0</version>
    </dependency>

    <dependency>
      <groupId>org.apache.commons</groupId>
      <artifactId>commons-collections4</artifactId>
      <version>4.1</version>
    </dependency>

    <!-- Spring Boot Mail -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-mail</artifactId>
    </dependency>

    <!-- Spring Boot Configuration Processor -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-configuration-processor</artifactId>
      <optional>true</optional>
    </dependency>

    <!-- Lombok -->
    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <version>${lombok.version}</version>
      <scope>provided</scope>
    </dependency>

    <!-- PDF page-splitting for Document (PDF) tasks -->
    <dependency>
      <groupId>org.apache.pdfbox</groupId>
      <artifactId>pdfbox</artifactId>
      <version>2.0.31</version>
    </dependency>

    <!-- ⇓ test dependencies ⇓ -->
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>org.springframework.security</groupId>
      <artifactId>spring-security-test</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>com.tngtech.archunit</groupId>
      <artifactId>archunit-junit5</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>com.socgen.apibank</groupId>
      <artifactId>apibank-gatling-security</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>com.socgen.sgs.sgs-stack</groupId>
      <artifactId>sgs-gatlingSgConnectHelper-plugin</artifactId>
      <scope>test</scope>
    </dependency>

    <dependency>
      <groupId>org.junit.vintage</groupId>
      <artifactId>junit-vintage-engine</artifactId>
      <scope>test</scope>
    </dependency>

    <!-- Spring Web Services for SOAP -->
    <dependency>
      <groupId>org.springframework.ws</groupId>
      <artifactId>spring-ws-core</artifactId>
    </dependency>

    <!-- JAXB for XML binding -->
    <dependency>
      <groupId>org.springframework</groupId>
      <artifactId>spring-oxm</artifactId>
    </dependency>

    <!-- JAXB Runtime for Java 11+ -->
    <dependency>
      <groupId>jakarta.xml.bind</groupId>
      <artifactId>jakarta.xml.bind-api</artifactId>
    </dependency>

    <dependency>
      <groupId>org.glassfish.jaxb</groupId>
      <artifactId>jaxb-runtime</artifactId>
    </dependency>

    <!-- Apache Axis 1.x runtime — required by classes generated from RPC/encoded WSDL -->
    <dependency>
      <groupId>org.apache.axis</groupId>
      <artifactId>axis</artifactId>
      <version>1.4</version>
    </dependency>

    <dependency>
      <groupId>org.apache.axis</groupId>
      <artifactId>axis-jaxrpc</artifactId>
      <version>1.4</version>
    </dependency>

    <dependency>
      <groupId>org.apache.axis</groupId>
      <artifactId>axis-saaj</artifactId>
      <version>1.4</version>
    </dependency>

    <dependency>
      <groupId>commons-discovery</groupId>
      <artifactId>commons-discovery</artifactId>
      <version>0.5</version>
    </dependency>

    <dependency>
      <groupId>commons-logging</groupId>
      <artifactId>commons-logging</artifactId>
      <version>1.2</version>
    </dependency>

    <dependency>
      <groupId>wsdl4j</groupId>
      <artifactId>wsdl4j</artifactId>
      <version>1.6.3</version>
    </dependency>

  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <configuration>
          <annotationProcessorPaths>
            <path>
              <groupId>org.projectlombok</groupId>
              <artifactId>lombok</artifactId>
              <version>${lombok.version}</version>
            </path>
          </annotationProcessorPaths>
        </configuration>
      </plugin>

    </plugins>
  </build>

  <repositories>
    <repository>
      <id>dsp-artifacts</id>
      <url>https://dsp-artifacts.fr.world.socgen/artifactory/maven-virtual-03bbaf52-d025-46b0-b487-49e464ef8c1b</url>
      <releases>
        <enabled>true</enabled>
      </releases>
      <snapshots>
        <enabled>true</enabled>
      </snapshots>
    </repository>
  </repositories>

  <pluginRepositories>
    <pluginRepository>
      <id>dsp-artifacts</id>
      <url>https://dsp-artifacts.fr.world.socgen/artifactory/maven-virtual-03bbaf52-d025-46b0-b487-49e464ef8c1b</url>
      <releases>
        <enabled>true</enabled>
      </releases>
      <snapshots>
        <enabled>true</enabled>
      </snapshots>
    </pluginRepository>
  </pluginRepositories>

  <profiles>
    <!--
      RequestService.wsdl is operationally stable. Normal builds compile the reviewed generated
      snapshot committed under src/main/java and never rewrite production sources.

      When an approved WSDL changes, generate a comparison snapshot explicitly with:
        mvn -Pregenerate-axis-review axistools:wsdl2java
      Review target/generated-sources/axis-review semantically before intentionally replacing the
      committed snapshot. This profile is not bound to the normal Maven lifecycle.
    -->
    <profile>
      <id>regenerate-axis-review</id>
      <build>
        <plugins>
          <plugin>
            <groupId>org.codehaus.mojo</groupId>
            <artifactId>axistools-maven-plugin</artifactId>
            <version>1.4</version>
            <configuration>
              <sourceDirectory>${project.basedir}/src/main/resources/wsdl</sourceDirectory>
              <wsdlFiles>
                <wsdlFile>RequestService.wsdl</wsdlFile>
              </wsdlFiles>
              <outputDirectory>${project.build.directory}/generated-sources/axis-review</outputDirectory>
              <timestampDirectory>${project.build.directory}/axistools-review-timestamps</timestampDirectory>
              <packageSpace>com.socgen.sgs.api.quark.engine.integration.soap.generated</packageSpace>
              <serverSide>false</serverSide>
              <testCases>false</testCases>
            </configuration>
          </plugin>
        </plugins>
      </build>
    </profile>
    <!--        <profile>-->
    <!--            <id>performance-tests</id>-->
    <!--            <build>-->
    <!--                <plugins>-->
    <!--                    <plugin>-->
    <!--                        <groupId>io.gatling</groupId>-->
    <!--                        <artifactId>gatling-maven-plugin</artifactId>-->
    <!--                        <version>4.6.0</version>-->
    <!--                    </plugin>-->
    <!--                </plugins>-->
    <!--            </build>-->
    <!--        </profile>-->
    <!--        <profile>-->
    <!--            <id>run-local</id>-->
    <!--            <build>-->
    <!--                <plugins>-->
    <!--                    <plugin>-->
    <!--                        <groupId>org.springframework.boot</groupId>-->
    <!--                        <artifactId>spring-boot-maven-plugin</artifactId>-->
    <!--                        <version>${spring-boot.version}</version>-->
    <!--                        <configuration>-->
    <!--                            <jvmArguments>-Dspring.profiles.active=local -Dspring.config.location=classpath:/,file:./src/main/config/local/</jvmArguments>-->
    <!--                        </configuration>-->
    <!--                    </plugin>-->
    <!--                </plugins>-->
    <!--            </build>-->
    <!--        </profile>-->
  </profiles>

  <scm>
    <connection>${sgithub.scm}/https://sgithub.fr.world.socgen/SGSS-FVS/quark-batch-job.git</connection>
    <developerConnection>${sgithub.scm}/https://sgithub.fr.world.socgen/SGSS-FVS/quark-batch-job.git</developerConnection>
    <tag>HEAD</tag>
  </scm>

  <distributionManagement>
    <snapshotRepository>
      <id>dsp-artifacts</id>
      <url>https://dsp-artifacts.fr.world.socgen:443/artifactory/maven-prereleases-private-03bbaf52-d025-46b0-b487-49e464ef8c1b/</url>
      <layout>default</layout>
    </snapshotRepository>
    <repository>
      <id>dsp-artifacts</id>
      <url>https://dsp-artifacts.fr.world.socgen:443/artifactory/maven-releases-private-03bbaf52-d025-46b0-b487-49e464ef8c1b/</url>
      <layout>default</layout>
    </repository>
  </distributionManagement>

</project>
```

## 2. `src/main/resources/application.yaml` — scoped edits only

Do not replace the full file. Keep the datasource, Rabbit host/credentials, QXPS URL/pool path, QXPSM endpoint and all
other existing values exactly as they are.

Inside the existing `spring.rabbitmq.listener.simple` block, make it exactly:

```yaml
    listener:
      simple:
        acknowledge-mode: auto
        default-requeue-rejected: false
        concurrency: 1
        max-concurrency: 1
        prefetch: 1
        retry:
          enabled: false
```

If that block already has these exact values, no edit is needed.

Remove these two obsolete, unused blocks if they are still present:

```yaml
qxp:
  thirdparty:
    url: http://srvcldvapd001.dns43.socgen:8080/saveas/pdf/

quark-engine:
  rabitmq:
    run: quark-batch-run-dev
```

`qxp.thirdparty` has no active engine consumer, and `quark-engine.rabitmq` is the misspelled legacy queue key. Their
removal leaves the existing `queue.runqueue` as the only Rabbit queue source.

Also verify, without adding a second block, that the Wave 10A settings remain present:

```yaml
engine:
  input:
    rabbit:
      enabled: false
```

Keep the existing single queue key:

```yaml
queue:
  runqueue: quark-batch-run-dev
```

Do not introduce `DATASOURCE_*`, `RABBITMQ_*`, `QXPS_SERVER_URL`,
`QXPS_POOL_DEFAULT_PATH`, `QXPSM_SOAP_ENDPOINT`, or `ENGINE_RABBIT_RUN_QUEUE` placeholders in this wave.
Those deployment-time substitutions are deferred.

## 3. `src/test/java/com/socgen/sgs/api/quark/engine/ApplicationContextSmokeTest.java`

SHA-256: `10b7e9a4e3fba4e331df1fade39b3eaa477398f76f4ed62de00c1d643bed37fb`

```java
package com.socgen.sgs.api.quark.engine;

import com.socgen.sgs.api.quark.engine.config.RabbitMqConfig;
import com.socgen.sgs.api.quark.engine.listener.RunMessageListener;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.url=jdbc:h2:mem:wave10d-context;MODE=PostgreSQL;DATABASE_TO_UPPER=TRUE;DEFAULT_NULL_ORDERING=HIGH",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.hikari.connection-init-sql=SELECT 1",
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.liquibase.enabled=false",
        "spring.rabbitmq.listener.simple.auto-startup=false",
        "engine.input.rabbit.enabled=false"
})
class ApplicationContextSmokeTest extends SpringBootITProfileWithTransactionalAndMockMvc {

    @Autowired
    private ApplicationContext applicationContext;

    @Test
    void completeApiOnlyContextStartsWithoutRabbitConsumerBeans() {
        assertThat(applicationContext).isNotNull();
        assertThat(applicationContext.getBeansOfType(RunMessageListener.class)).isEmpty();
        assertThat(applicationContext.getBeansOfType(RabbitMqConfig.class)).isEmpty();
    }
}
```

## Files intentionally unchanged

- `.gitignore`
- `src/test/resources/application-test.yaml`
- every file under `src/main/config/local`
- every file under `src/main/config/env`
- every file under `src/main/config/secrets`
- `Jenkinsfile`: team-lead/organization handoff; still a deployment gate
- `src/main/resources/wsdl/RequestService.wsdl`: stable reviewed WSDL
- all 276 files under `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/generated`: reviewed committed snapshot

## Required verification after all Wave 10 files are copied

1. Confirm the main YAML contains only one `queue.runqueue`, no `quark-engine.rabitmq` block, and one
   `engine.input.rabbit.enabled` definition.
2. Confirm `engine.input.rabbit.enabled: false`.
3. Run `mvn clean install` with Java 21 and tests enabled.
4. Run it a second time.
5. Confirm both builds pass and the second build does not rewrite tracked source files.
6. Confirm `ApplicationContextSmokeTest` executes and no Rabbit listener/configuration bean is created.
7. Do not test Rabbit until the DLQ, repeated-ID and publisher-confirm gates are closed.

## Deferred deployment work

Before any production deployment, explicitly revisit:

- datasource, Rabbit and document-service endpoint/credential externalization;
- credential rotation for values already committed in source/history;
- environment-specific configuration ownership;
- Jenkins branch/config-map/secret mapping;
- container/Dockerfile readiness.

These items are deferred, not closed.
