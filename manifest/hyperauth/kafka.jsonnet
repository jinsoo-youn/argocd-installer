function (
  is_offline="false",
  private_registry="172.22.6.2:5000",
  hyperauth_svc_type="Ingress",
  hyperauth_external_ip="172.22.6.8",
  is_kafka_enabled="true",
  hyperauth_subdomain="hyperauth",
  hypercloud_domain_host="tmaxcloud.org",
  storage_class="default",
  timezone_setting="UTC",
  self_signed="false",
  log_level="INFO",
)

if is_kafka_enabled == "true" then [
  {
    "apiVersion": "kafka.strimzi.io/v1beta2",
    "kind": "Kafka",
    "metadata": {
      "name": "kafka",
      "namespace": "hyperauth",
      // kafka crd 없이 dry-run 방식으로 생성
      "annotations": {
        "argocd.argoproj.io/sync-options": "SkipDryRunOnMissingResource=true"
      },
    },
    "spec": {
      "kafka": {
        "version": "3.3.1",
        "replicas": 3,
        "resources": {
            "limits": {
              "cpu": "1000m",
              "memory": "2Gi"
            },
            "requests": {
              "cpu": "100m",
              "memory": "100Mi"
            }
        },
        "listeners": [
          {
            "name": "plain",
            "port": 9092,
            "type": "internal",
            "configuration": {
              "brokerCertChainAndKey": {
                "secretName": "kafka-jks",
                "certificate": "tls.crt",
                "key": "tls.key"
              }
            },
            "tls": true
          }
        ],
        "logging": {
          "type": "inline",
          "loggers": {
            "log4j.logger.io.strimzi": "TRACE",
            "log4j.logger.kafka": "DEBUG",
            "log4j.logger.org.apache.kafka": "DEBUG"
          }
        },
        "config": {
          "offsets.topic.replication.factor": 3,
          "transaction.state.log.replication.factor": 1,
          "transaction.state.log.min.isr": 1,
          "log.message.format.version": "2.8",
          "inter.broker.protocol.version": "2.8"
        },
        "storage": {
          "type": "persistent-claim",
          "size": "10Gi"
        },
        "metricsConfig": {
          "type": "jmxPrometheusExporter",
          "valueFrom": {
            "configMapKeyRef": {
              "name": "kafka-metrics",
              "key": "kafka-metrics-config.yml"
            }
          }
        }
      },
      "zookeeper": {
        "replicas": 3,
        "resources": {
            "limits": {
              "cpu": "1000m",
              "memory": "2Gi"
            },
            "requests": {
              "cpu": "100m",
              "memory": "100Mi"
            }
        },
        "storage": {
          "type": "persistent-claim",
          "size": "1Gi"
        },
        "metricsConfig": {
          "type": "jmxPrometheusExporter",
          "valueFrom": {
            "configMapKeyRef": {
                "name": "kafka-metrics",
                "key": "zookeeper-metrics-config.yml"
            }
          }
        }
      },
      "entityOperator": {
        "topicOperator": {},
        "userOperator": {}
      },
      "kafkaExporter": {
        "topicRegex": ".*",
        "groupRegex": ".*"
      }
    }
  },
  {
    "kind": "ConfigMap",
    "apiVersion": "v1",
    "metadata": {
      "name": "kafka-metrics",
      "namespace": "hyperauth",
      "labels": {
        "app": "strimzi"
      }
    },
    "data": {
      "kafka-metrics-config.yml": std.join("\n", 
        [
          "# See https://github.com/prometheus/jmx_exporter for more info about JMX Prometheus Exporter metrics",
          "lowercaseOutputName: true",
          "rules:",
          "# Special cases and very specific rules",
          "- pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value",
          "  name: kafka_server_$1_$2",
          "  type: GAUGE",
          "  labels:",
          "    clientId: \"$3\"",
          "    topic: \"$4\"",
          "    partition: \"$5\"",
          "- pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), brokerHost=(.+), brokerPort=(.+)><>Value",
          "  name: kafka_server_$1_$2",
          "  type: GAUGE",
          "  labels:",
          "    clientId: \"$3\"",
          "    broker: \"$4:$5\"",
          "- pattern: kafka.server<type=(.+), cipher=(.+), protocol=(.+), listener=(.+), networkProcessor=(.+)><>connections",
          "  name: kafka_server_$1_connections_tls_info",
          "  type: GAUGE",
          "  labels:",
          "    listener: \"$2\"",
          "    networkProcessor: \"$3\"",
          "    protocol: \"$4\"",
          "    cipher: \"$5\"",
          "- pattern: kafka.server<type=(.+), clientSoftwareName=(.+), clientSoftwareVersion=(.+), listener=(.+), networkProcessor=(.+)><>connections",
          "  name: kafka_server_$1_connections_software",
          "  type: GAUGE",
          "  labels:",
          "    clientSoftwareName: \"$2\"",
          "    clientSoftwareVersion: \"$3\"",
          "    listener: \"$4\"",
          "    networkProcessor: \"$5\"",
          "- pattern: \"kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+):\"",
          "  name: kafka_server_$1_$4",
          "  type: GAUGE",
          "  labels:",
          "    listener: \"$2\"",
          "    networkProcessor: \"$3\"",
          "- pattern: kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+)",
          "  name: kafka_server_$1_$4",
          "  type: GAUGE",
          "  labels:",
          "    listener: \"$2\"",
          "    networkProcessor: \"$3\"",
          "# Some percent metrics use MeanRate attribute",
          "# Ex) kafka.server<type=(KafkaRequestHandlerPool), name=(RequestHandlerAvgIdlePercent)><>MeanRate",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)Percent\\w*><>MeanRate",
          "  name: kafka_$1_$2_$3_percent",
          "  type: GAUGE",
          "# Generic gauges for percents",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)Percent\\w*><>Value",
          "  name: kafka_$1_$2_$3_percent",
          "  type: GAUGE",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)Percent\\w*, (.+)=(.+)><>Value",
          "  name: kafka_$1_$2_$3_percent",
          "  type: GAUGE",
          "  labels:",
          "    \"$4\": \"$5\"",
          "# Generic per-second counters with 0-2 key/value pairs",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)PerSec\\w*, (.+)=(.+), (.+)=(.+)><>Count",
          "  name: kafka_$1_$2_$3_total",
          "  type: COUNTER",
          "  labels:",
          "    \"$4\": \"$5\"",
          "    \"$6\": \"$7\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)PerSec\\w*, (.+)=(.+)><>Count",
          "  name: kafka_$1_$2_$3_total",
          "  type: COUNTER",
          "  labels:",
          "    \"$4\": \"$5\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)PerSec\\w*><>Count",
          "  name: kafka_$1_$2_$3_total",
          "  type: COUNTER",
          "# Generic gauges with 0-2 key/value pairs",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Value",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "  labels:",
          "    \"$4\": \"$5\"",
          "    \"$6\": \"$7\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.+)><>Value",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "  labels:",
          "    \"$4\": \"$5\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)><>Value",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "# Emulate Prometheus 'Summary' metrics for the exported 'Histogram's.",
          "# Note that these are missing the '_sum' metric!",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Count",
          "  name: kafka_$1_$2_$3_count",
          "  type: COUNTER",
          "  labels:",
          "    \"$4\": \"$5\"",
          "    \"$6\": \"$7\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.*), (.+)=(.+)><>(\\d+)thPercentile",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "  labels:",
          "    \"$4\": \"$5\"",
          "    \"$6\": \"$7\"",
          "    quantile: \"0.$8\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.+)><>Count",
          "  name: kafka_$1_$2_$3_count",
          "  type: COUNTER",
          "  labels:",
          "    \"$4\": \"$5\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+), (.+)=(.*)><>(\\d+)thPercentile",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "  labels:",
          "    \"$4\": \"$5\"",
          "    quantile: \"0.$6\"",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)><>Count",
          "  name: kafka_$1_$2_$3_count",
          "  type: COUNTER",
          "- pattern: kafka.(\\w+)<type=(.+), name=(.+)><>(\\d+)thPercentile",
          "  name: kafka_$1_$2_$3",
          "  type: GAUGE",
          "  labels:",
          "    quantile: \"0.$4\"",
          ""
        ]
      ),
      "zookeeper-metrics-config.yml": std.join("\n",
        [
          "# See https://github.com/prometheus/jmx_exporter for more info about JMX Prometheus Exporter metrics",
          "lowercaseOutputName: true",
          "rules:",
          "# replicated Zookeeper",
          "- pattern: \"org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\\\d+)><>(\\\\w+)\"",
          "  name: \"zookeeper_$2\"",
          "  type: GAUGE",
          "- pattern: \"org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\\\d+), name1=replica.(\\\\d+)><>(\\\\w+)\"",
          "  name: \"zookeeper_$3\"",
          "  type: GAUGE",
          "  labels:",
          "    replicaId: \"$2\"",
          "- pattern: \"org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\\\d+), name1=replica.(\\\\d+), name2=(\\\\w+)><>(Packets\\\\w+)\"",
          "  name: \"zookeeper_$4\"",
          "  type: COUNTER",
          "  labels:",
          "    replicaId: \"$2\"",
          "    memberType: \"$3\"",
          "- pattern: \"org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\\\d+), name1=replica.(\\\\d+), name2=(\\\\w+)><>(\\\\w+)\"",
          "  name: \"zookeeper_$4\"",
          "  type: GAUGE",
          "  labels:",
          "    replicaId: \"$2\"",
          "    memberType: \"$3\"",
          "- pattern: \"org.apache.ZooKeeperService<name0=ReplicatedServer_id(\\\\d+), name1=replica.(\\\\d+), name2=(\\\\w+), name3=(\\\\w+)><>(\\\\w+)\"",
          "  name: \"zookeeper_$4_$5\"",
          "  type: GAUGE",
          "  labels:",
          "    replicaId: \"$2\"",
          "    memberType: \"$3\"",
          ""
        ]
      )
    }
  }
] else []