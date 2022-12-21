## ユニットテストの追加
ユニットテストをパイプラインに追加します。  
このアプリケーションでは、MySQLをバックエンドDBに利用しておりユニットテストでもMySQLおよびデータが必要です。

ユニットテストにおいて、DBを用意して実行するかどうかは別の議論としてありますが、<u>テストごとにクリーンなDBを用意できること、速度に影響がでないこと</u>、という条件を満たしていればDBを用意してテストしたいことは多いはずです。

Tektonでは、サイドカーコンテナを用いてテスト用のDBを用意できます。テストが終わったらDBをすぐに破棄します。サイドカーであれば、同一Pod内の別コンテナとして起動可能であり、アプリケーションからみて`localhost`としてDBにアクセスできます。

`pytest-with-mysql.yaml` は TektonHubの[pytest](https://hub.tekton.dev/tekton/task/pytest)を、アプリケーションに合わせてカスタマイズしたものです。サイドカーコンテナの追加と、データの初期化フェーズを追加しています。

```yaml
## pytest-with-mysql.yaml(抜粋)
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

パイプラインにも修正が必要です。修正後のパイプラインは「ソリューション」で提供しています。  
以下のように、`unit-test`のフェーズを追加しています。その他、変数が増え、`runAfter`も調整しています。

```yaml
## build-pipeline-with-ut.yaml(抜粋)
...
   - name: unit-test
      taskRef:
        name: pytest-with-mysql
      params:
        - name: PYTHON
          value: $(params.python-version)
      workspaces:
        - name: source
          workspace: shared-workspace
      runAfter:
        - fetch-repository
```

### ソリューション

```
## 自作pytest taskのインストール
$ oc apply -f docs/solutions/pytest-with-mysql.yaml

## 拡張したパイプラインのインストール
$ oc apply -f docs/solutions/build-pipeline-with-ut.yaml
```

作成したパイプラインを実行しましょう。  
実行方法は、前回の `build-pipeline` とほぼ同じですが、`python-version` の指定箇所が増えています。本アプリは `3.9` で動作するので、`python-version=3.9` で実行が可能です。


## Sonarqubeを使った静的解析の追加
Sonarqubeは、ソースコードの「ソフトウェアメトリクス（複雑性、保守性など、特定の側面を定量的に示す指標）」や、ソースコードに潜む欠陥や潜在的なリスクの検出できるツールです。  
特徴的な機能に[QualityGate](https://docs.sonarqube.org/latest/user-guide/quality-gates/)があります。この機能は、取得したソフトウェアメトリクスや、静的解析の結果、一定基準のスコアを満たさなかった場合に、検知することでデプロイを止めることができるものです。

TektonでSonarqubeを用いた静的解析を追加します。  
すでに [sonarqube-scanner](https://hub.tekton.dev/tekton/task/sonarqube-scanner)のTaskが用意されているのでそのまま使います。

### ソリューション
まずは、sonarqubeへアクセスして、プロジェクトを作成します。プロジェクト名は `userX-python-app` としてください。（`userX`は自分のユーザ名に読み替えてください。）

![](/docs/images/sonarqube-create-project.png)

プロジェクトを作成したあと、プロジェクト画面にて「Locally」を選択し、トークンを取得します。トークンはあとで利用するためコピーしておきます。

![](/docs/images/sonarqube-ci-select.png)

![](/docs/images/sonarqube-generate-token.png)

```
## TokenをOpenShiftに登録
$ oc create secret generic sonarqube-key --from-literal=login=xxxxxxxxxxxxxxx

## sonarqube-scanner taskのインストール
$ oc apply -f https://api.hub.tekton.dev/v1/resource/tekton/task/sonarqube-scanner/0.4/raw 

## 拡張したパイプラインのインストール
$ oc apply -f docs/solutions/build-pipeline-with-ut-sonar.yaml
```

実行時のパラメータ例は以下です。

- パラメータ
  - git-url
    - `https://github.com/mosuke5/openshift-pipelines-gitops-practice`
  - git-revision
    - `main`
  - image
    - `image-registry.openshift-image-registry.svc:5000/<ns>/<image name>`
    - `image-registry.openshift-image-registry.svc:5000/user10-staging/myapp`
  - image-tag
    - `latest`
    - 任意でもOK
  - context
    - `.`
    - Dockerfileのある場所
  - python-version
    - `3.9`
  - sonar-host-url
    - `http://sonarqube-sonarqube.handson-devops:9000`
  - sonar-project-key
    - `userX-python-app`
    - 例）user10-python-app
- ワークスペース
  - shared-workspace
    - `ボリューム要求テンプレート`
  - sonar-settings
    - `空のディレクトリー`
  - sonar-credentials
    - `シークレット`を選択し、前工程で作成したシークレットを指定（手順通りであれば `sonarqube-key`）。

パイプラインが無事に終了することを確認します。
![](/docs/images/sonarqube-pipeline.png)

パイプラインが成功すると、Sonarqubeにも解析結果が表示されます。
![](/docs/images/sonarqube-result.png)

### Sonarqubeの探索
Sonarqubeでは、さまざまなメトリクスを取得しています。
特に`Measures`の中身を確認しておくと面白いでしょう。

- Complexity
  - コードの複雑度です。このアプリケーションではコード量が少ないので参考になりづらいですが、今後皆さんのアプリケーションを解析するときは役に立つでしょう。
- Duplications
  - コードの重複度
- Coverage
  - 単体テストのカバレッジ。

### CLIで実行する場合の例
```
tkn pipeline start build-pipeline-with-ut-sonar \
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