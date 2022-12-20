## ハンズオン管理者向け事前準備
ハンズオン管理者で事前にSonarqubeを起動しておきます。 `handson-devops` プロジェクト内にSonarqubeが起動していることを前提に以下すすめます。

```
$ oc new-project handson-devops
$ oc create sa postgresql
$ oc adm policy add-scc-to-user anyuid -z postgresql

$ helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
$ helm repo update
$ helm upgrade --install -f docs/solutions/sonarqube.yaml -n handson-devops sonarqube sonarqube/sonarqube
```

default: admin/admin

## ユニットテストの追加
ユニットテストをパイプラインに追加します。  
このアプリケーションでは、MySQLをバックエンドDBに利用しておりユニットテストでもMySQLおよびデータが必要です。

ユニットテストにおいて、DBを用意して実行するかどうかは別の議論としてありますが、テストごとにクリーンなDBを用意できること、速度に影響がでないこと、という条件を満たしていればDBを用意してテストしたいことは多いはずです。

Tektonでは、サイドカーコンテナを用いてテスト用のDBを用意して、終わったら破棄できます。サイドカーであれば、同一Pod内の別コンテナとして起動可能であり、アプリケーションからみて`localhost`としてDBにアクセスできます。

`pytest-with-mysql.yaml` は [pytest](https://hub.tekton.dev/tekton/task/pytest)をアプリケーションに合わせて、サイドカーコンテナをの追加と、データの初期化フェーズを追加したものです。

```yaml
  steps:
    - name: initialize-data
      image: $(inputs.params.MYSQL_IMAGE)
      workingDir: $(workspaces.source.path)
      script: |
        ## wait for starting mysql
        timeout 180 bash -c 'until printf "" 2>>/dev/null >>/dev/tcp/$0/$1; do sleep 1; done' localhost 3306
        /bin/bash db/init.sh
    - name: unit-test
      image: docker.io/python:$(inputs.params.PYTHON)
      workingDir: $(workspaces.source.path)
      script: |
        ....
  sidecars:
    - image: $(inputs.params.MYSQL_IMAGE)
      name: mysql
      env:
        - name: MYSQL_DATABASE
          value: $(inputs.params.MYSQL_DATABASE)
        - name: MYSQL_USER
          value: $(inputs.params.MYSQL_USER)
        - name: MYSQL_PASSWORD
          value: $(inputs.params.MYSQL_PASSWORD)
```

## Sonarqubeを使った静的解析の追加
Sonarqubeは、ソースコードの「ソフトウェアメトリクス（複雑性、保守性など、特定の側面を定量的に示す指標）」や、ソースコードに潜む欠陥や潜在的なリスクの検出できるツールです。  
特徴的な機能に[QualityGate](https://docs.sonarqube.org/latest/user-guide/quality-gates/)があります。この機能は、取得したソフトウェアメトリクスや、静的解析の結果、一定基準のスコアを満たさなかった場合に、検知することでデプロイを止めることができるものです。

TektonでSonarqubeを用いた静的解析を追加します。  
すでに [sonarqube-scanner](https://hub.tekton.dev/tekton/task/sonarqube-scanner)のTaskが用意されているのでそのまま使います。

## ソリューション
```
## sonarqube-scanner taskのインストール
$ oc apply -f https://api.hub.tekton.dev/v1/resource/tekton/task/sonarqube-scanner/0.4/raw 

## 自作pytest taskのインストール
$ oc apply -f docs/solutions/pytest-with-mysql.yaml

## 拡張したパイプラインのインストール
$ oc apply -f docs/solutions/extended-pipeline.yaml
```

`extended-pipeline`を実行し以下を確認しましょう。

1. unit-testフェーズが追加されていること
1. サイドカーコンテナでMySQLが起動し、テストが実行できていること
1. SonarQubeへスキャン情報が登録されていること
1. SonarQubeの結果がパスすること

```
tkn pipeline start build-pipeline-with-sonar \
--use-param-defaults \
--param git-url=https://github.com/mosuke5/openshift-pipelines-gitops-practice \
--param git-revision=main \
--param image=image-registry.openshift-image-registry.svc:5000/user0-staging/myapp \ 
--param image-tag=latest \
--param context="." \
--workspace name=shared-workspace,volumeClaimTemplateFile=docs/solutions/workspace-template.yaml \
--workspace name=sonar-settings,emptyDir="" \
--workspace name=sonar-credentials,secret=sonarqube-key
```