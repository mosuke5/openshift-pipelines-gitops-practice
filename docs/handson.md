# ハンズオン
## 0. 確認した環境
- OpenShift: 4.10, 4.11
- OpenShift Piplines: 1.8
- OpenShift GitOps: 1.6

## 1. Argo CDの基礎
Kubernetesを活用したアプリケーションデプロイを学ぶためにArgo CDを利用して、GitOpsの概念を理解します。
次のレポジトリの「ハンズオン１」を完了させましょう。
ハンズオンで利用するArgo CDについては、ハンズオン主催者が事前に作成済みです。

[Argo CD基礎ハンズオン](https://github.com/mamoru1112/openshift-gitops-handson)

## 2. Tetkonの基礎
Kubernetes環境で用いられるクラウドネイティブなCIツールであるTektonの基礎概念を理解します。次のハンズオンを完了させましょう。

[Tekton基礎ハンズオン](/docs/tekton.md)

## 3. アプリケーションを理解とOpenShiftの基本操作
本アプリケーションは、Python flask+MySQLで動作するAPIサーバです。
まずは、アプリケーションを[README.md](README.md)にしたがって動かしてみましょう。
OpenShiftの基本操作について問題ない人はアプリケーションの動かし方だけ把握するでも構いません。

1. 開発環境整備
    - サンプルアプリケーションを開発環境（自身のPCや開発サーバ）にて、起動しましょう。起動方法例については、レポジトリのREADME.mdに記載があります。
1. アプリケーションビルドとデプロイ
    - サンプルアプリケーションのコンテナイメージを作成しましょう。Dockerfile or S2Iでもどちらでも構いません。（データベースについては、既存のコンテナイメージをぜひ利用しましょう）
    - 作成したコンテナイメージを、OpenShiftで動作するようにマニフェストを準備しましょう。次の要件を満たすようにしましょう。
        - アプリケーションは、クラスタ外部から接続できるように公開しましょう。（Deployment, Service, Route, ConfigMap, Secretなどを準備）
        - データベースへの接続ID/PWは、Secretオブジェクトに切り出し環境変数としてアプリケーションに渡しましょう。
        - データベースのデータ領域にはPVをマウントしましょう。また、データベースの起動にはStatefulSetを利用てみましょう。※利用できるPVが用意できない場合は、emptyDirで代用を検討してください。
        - （オプション）OpenShiftテンプレートやKustomizeなどテンプレートエンジンを利用しましょう。
    - （オプション）アプリケーションの前段にWebサーバ（NginxやApache httpdなど）を配置してみましょう。Webサーバを配置するモチベーションとしては、静的コンテンツのキャッシュやIP制限、Basic認証などを設定すると仮定してください。その際、Webサーバの設定ファイルはConfigMapで管理してみましょう。
1. オペレーション
    - アプリケーションにアクセスし、oc logsを用いてログを確認してみましょう。
    - アプリケーションに対して、ReadinessProbeとLivenessProbeを設定しましょう。その際、ReadinessProbeとLivenessProbeの違いを明確にしておきましょう。
    - アプリケーションのレプリカ数を変更し（2以上に設定し）、負荷分散が行われる状況を確認しましょう。
    - アプリケーションの一部を変更し、手動で更新したアプリケーションをデプロイし、その変更を確認してみましょう。

## 4. アプリケーションへの適用
本レポジトリのIsuumo pythonアプリに、ビルドパイプラインとArgoCDを用いたデプロイ処理を加えてみましょう。  
今回のハンズオンで実施する全体像は以下です。

<img width="1063" alt="スクリーンショット 2021-08-22 17 46 39" src="https://user-images.githubusercontent.com/733334/130348499-88ef2f1e-21bf-4769-96f2-bb143f408a5d.png">

### 4-1. リソース
- ソースコードレポジトリ: https://github.com/mosuke5/openshift-pipelines-gitops-practice
- マニフェストレポジトリ: https://github.com/mosuke5/migration-practice-for-flask-manifests
    - PythonアプリとMySQLのデプロイをKustomizeで行う

### 4-2. 事前準備
事前準備として、ふたつのProject(namespace)の作成と、production用のProjectから、Staging用のImage Streamにアクセスできるように権限付与しておきます。
`userX`は任意の値に変えてください。

```
$ oc new-project userX-production
$ oc new-project userX-staging
$ oc adm policy add-role-to-user view system:serviceaccount:userX-production:default -n userX-staging
```

### 4-3. CIパイプラインの作成
まずは、ビルドパイプラインの作成を行います。
以下は、雛形のPipelineマニフェストです。必要なパラメータを調べて埋めて実行してみましょう(TODO箇所)。
アコーディオン内に動作する答えも用意しているので、必要に応じて見ながら進めてみましょう。

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-pipeline
spec:
  # 'fetch-repository'と'build-push-image'でソースコードを共有するためのストレージ
  workspaces: 
    - name: shared-workspace
  params:
    - name: git-url
      type: string
    - name: git-revision
      type: string
      default: "main"
    - name: image
      type: string
      default: "image-registry.openshift-image-registry.svc:5000/<ns>/<image name>"
    - name: image-tag
      type: string
      default: "latest"
    - name: context
      type: string
      default: "."
  tasks:
    - name: fetch-repository
      taskRef:
        name: git-clone
        kind: ClusterTask
      # 'fetch-repository'と'build-push-image'でソースコードを共有するためのストレージ
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.git-url)
        - name: deleteExisting
          value: "true"
        - name: revision
          value: $(params.git-revision)
    - name: build-push-image
      taskRef:
        name: buildah
        kind: ClusterTask
      params:
      　　 # [TODO] buildah　Taskを確認し、必要なパラメータを確認して記述してみましょう
         
      # 'fetch-repository'と'build-push-image'でソースコードを共有するためのストレージ
      workspaces:
        - name: source
          workspace: shared-workspace
      runAfter:
        - fetch-repository
```


<details>
<summary>ビルドパイプラインのソリューション</summary>
<div>

  [build-pipeline.yaml](/docs/solutions/build-pipeline.yaml) が実装例です。
  
  ```
  $ oc apply -f docs/solutions/build-pipeline.yaml
  ```
    
</div>
</details>

### 4-4. CIパイプラインの実行
作成したCIパイプラインは、実行して正しくビルドされるか確認してみましょう。  
前手順で、`PipelineRun`リソースを使用したため、同じ用に`PipelineRun`マニフェストを記述しても実行もできますが、OpenShiftのWebコンソールからパラメータを入力し実行することもできます。一度試してみましょう。

Webコンソールのサイドバー「パイプライン」から、作成したパイプラインを選択し、「アクション」 -> 「開始」から実行できます。　　
パラメータには以下を指定しましょう。

- `git-url`: イメージをビルドするために使うソースコードレポジトリ。フォークした場合はフォーク先のレポジトリ。
- `git-revision`: Gitのブランチ。何も変更なければ`main`となる。
- `image`: ビルドしたイメージをプッシュする先。今回はOpenShiftの内部レジストリを使うため、次の命名規則となる。`<image name>`は任意の値。
  - `image-registry.openshift-image-registry.svc:5000/<ns>/<image name>`
- `image-tag`: イメージにつけるタグ。
- `context`: Dockerfileのおいてある階層

<img width="878" alt="スクリーンショット 2021-08-22 16 48 44" src="https://user-images.githubusercontent.com/733334/130346961-faf483d8-322a-4319-8840-25f6cce201e4.png">

Workspace設定は、「ボリューム要求テンプレート」を選択し、以下の設定としてください。  
本環境は、AWS上で動いているため、EBSボリュームを払い出してタスク実行に利用します。

<img width="870" alt="スクリーンショット 2021-08-22 16 49 03" src="https://user-images.githubusercontent.com/733334/130346979-43799fa5-6459-47c9-897c-3047966ad68c.png">


実施すること
- Pipelineの作成
- Pipelineの実行
- 実行結果の確認
  - Image Streamにイメージが格納されていることを確認

### 4-5. (オプション)パイプラインの拡張
[パイプラインの拡張](/docs/extend-pipeline.md)

### 4-6. Argo CDを用いたデプロイ
Argo CDへアクセスし、[Argo CDハンズオンの内容](https://github.com/mamoru1112/openshift-gitops-handson)を思い出しながらデプロイ設定をしましょう。本演習で実施する流れは以下のとおりです。

1. Argo CDへのログイン
2. Production用とStaging用両方のAPPLICATION（Argo CD内）を作成しましょう。
    - マニフェストレポジトリは、`main`と`staging`の２つのブランチを用意しています。`main`ブランチをProduction用、`staging`ブランチをStaging用とし、APPLICATIONを作成してみましょう。
    - デプロイ先は、事前準備で作成した２つのnamespaceにデプロイできるようにしてみましょう。`main`ブランチの変更は `userX-production`へ、`staging`ブランチの変更は `userX-staging`へデプロイしましょう。
    - 詳細設定方法は後述します。
3. Production用とStaging用、両方のAPPLICATIONをデプロイしてみましょう
4. その後、Staging用ブランチになんらかの変更を加え反映してみましょう。
5. 4.が問題なければ、Stagingブランチの変更をmainブランチにマージ（プルリクエストの発行とマージ）し、Production用に反映してみましょう

Argo CDの設定例。

- SOURCE
    - Repository URL: フォークしたみなさんのGitHubレポジトリ
    - Revision: `main`か`staging`を選択
    - Path: Revision=`main`の場合は`production`を、 Revision=`staging`の場合は`staging`を選択。このPathは、レポジトリ内のどのPathを利用するか。Kustomizeで環境ごとにパラメータを変更してデプロイすることを想定しています。
- DESTINATION
    - Cluster URL: `https://kubernetes.default.svc`
    - Namespace: デプロイ先のnamespace。Production用であれば`userX-production`, Staging用であれば`userX-staging`を選択
- Kustomize（SOURCE設定でKustomizeアプリケーションと判定される） 
    - IMAGES:
    -  `image-registry.openshift-image-registry.svc:5000/<namespace name>/<image name>`は、皆さんの環境に合わせて書き換えてください。CIパイプラインでビルドしたイメージのパスです。わからない場合は、Webコンソールのサイドバーの「ビルド」 > 「イメージストリームタグ」から確認しましょう。
    -  `image-registry.openshift-image-registry.svc:5000/openshift/mysql`は、MySQLのイメージのため特に書き換えなくても大丈夫です。


実施すること
- `userX-staging`にアプリケーションをデプロイできること
- `userX-production`にアプリケーションをデプロイできること
- `userX-staging`のみに変更を適用できること。そして、動作確認後、`userX-production`に変更を適用できること。

### 4-7. Webhookの設定
#### Tekton Triggers
Tekton Pipelinesを用いたパイプラインの作成方法について説明しました。  
続いて、Tekton Triggersについて説明します。Tekton Triggersは、Tekton Pipelinesと連携したコンポーネントであり、Webhook等の外部イベントをトリガーにしてパイプラインを実行するソフトウェアです。OpenShift Pipelinesは、このトリガー機能も含みます（OpenShift Pipelines 1.5では、Tekton Triggersはまだテクノロジープレビュー状態であることに注意してください）。Tekton Triggersに登場する主要な概念をテーブルにまとめました。

| エンティティ | 説明 |
----|---- 
| Trigger Templates | PipelineRunを生成するためのテンプレート。PipelineRunを生成するために必要なパラメータの定義でき、パラメータを引き渡してPipelineRunを生成できる。 |
| Trigger Bindings | EventListenersが受け取ったデータ（たとえば、Webhookのペイロード）と、TriggerTemplatesに引き渡すパラメータの紐付け定義。 |
| ClusterTrigger Binding | すべてのNamespace/Projectで共有できるTriggerBindings。GitHubやGitlabといったメジャーなGitレポジトリからのイベントなどの汎用的なTriggerBindingsを管理。 |
| EventListener | Listener Podを生成してイベント（httpリクエスト）を待ち受ける。リクエストを受け付けるとTriggerBindings, TriggerTemplatesの設定を参照して、PipelineRunを生成する（パイプラインを実行する）。EventListenerには、オプションで追加できるInterceptorと呼ばれる機能を備える。GitHubやGitlabといったメジャーなGitレポジトリからのWebhookのバリデーションやフィルタリングができる。 |


OpenShift Pipelinesには、インストール時にいくつかのClusterTriggerBindingsが登録されています。Bitbucket, GitHub, GitlabのGitレポジトリを利用している場合、そのWebhookを処理できます。

```
$ oc get clustertriggerbindings
NAME                                    AGE
bitbucket-pullreq                       3d9h
bitbucket-pullreq-add-comment           3d9h
bitbucket-push                          3d9h
github-pullreq                          3d9h
github-pullreq-review-comment           3d9h
github-push                             3d9h
gitlab-mergereq                         3d9h
gitlab-push                             3d9h
gitlab-review-comment-on-commit         3d9h
gitlab-review-comment-on-issues         3d9h
gitlab-review-comment-on-mergerequest   3d9h
gitlab-review-comment-on-snippet        3d9h

$ oc get clustertriggerbindings github-push -o yaml
...
spec:
  params:
  - name: git-revision
    value: $(body.head_commit.id)
  - name: git-commit-message
    value: $(body.head_commit.message)
  - name: git-repo-url
    value: $(body.repository.url)
  - name: git-repo-name
    value: $(body.repository.name)
  - name: content-type
    value: $(header.Content-Type)
  - name: pusher-name
    value: $(body.pusher.name)
```

#### Tekton Triggersを用いたGitHubとの連携
前の項番で作成したパイプラインは、実行するために、PipelineRunを自ら作成する必要がありました。しかし、実際の運用においては、Gitレポジトリのアクションをトリガーにパイプラインを実行することで、継続的なインテグレーション・デリバリーを実現します。作成したパイプラインに対して、GitHubからのWebhookトリガーを追加します。サンプルのトリガーの概要を以下に示します。

![スクリーンショット 2021-08-22 22 10 00](https://user-images.githubusercontent.com/733334/130356481-07fdcbb9-a175-44a4-9636-2b6140364b4e.png)

Webhookによるトリガーを実現するためには、EventListenerを作成する必要があります。  
EventListenerの作成に先立ち、2つの準備が必要です。1つ目が、EventListenerが利用するService Accountの準備とその権限付与です。EventListenerの実態はPodです。イベントを受け付けたEventListenerが、PipelineRunを作成するため、EventListenerに対してKubernetesリソースを操作できる権限が必要になります。2つ目が、GitHub interceptorが認証に利用するシークレットです。Webhookイベントを送信するあらゆるリクエストに対してパイプラインを実行するのはセキュリティ面で危険であり、EventListenerにて認証を行います。

GitHub interceptorが利用するシークレットを作成します。シークレットのキーは任意のものに差し替えて利用してください。

```
$ oc project userX-staging

# EventListenerが利用するシークレットの作成
$ oc create secret generic github-webhook --from-literal=secretkey=openshift-handson
secret/github-webhook created
```

次に、以下のマニフェストを利用して、EventListenerとTriggerTemplateを作成します。TriggerBindingには、OpenShift Pipelinesで事前登録されているClusterTriggerBindingの’github-push’を活用します。`.spec.params`内のimageのデフォルト値は任意のものに変更してください。

```yaml
# trigger.yaml
apiVersion: triggers.tekton.dev/v1alpha1
kind: TriggerTemplate
metadata:
  name: build-pipeline
spec:
  params:
    - name: git-revision
      description: The git revision
      default: main
    - name: git-repo-url
      description: The git repository url
    - name: image
      description: The image url where build task push
      default: image-registry.openshift-image-registry.svc:5000/userX-staging/xxxx
    - name: context
      default: .
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: build-pipeline-run-
      spec:
        # 呼び出すPipelineの指定
        pipelineRef:
          name: build-pipeline
        params:
          - name: git-url
            value: $(tt.params.git-repo-url)
          - name: git-revision
            value: $(tt.params.git-revision)
          - name: image
            value: $(tt.params.image)
          - name: context
            value: $(tt.params.context)
        workspaces:
          - name: shared-workspace
            volumeClaimTemplate:
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 1Gi
---
apiVersion: triggers.tekton.dev/v1alpha1
kind: EventListener
metadata:
  name: build-pipeline
spec:
  # OpenShift Pipelinesによって作成されるSA
  serviceAccountName: pipeline
  triggers:
    - bindings:
        # OpenShift Pipelinesで登録済みのClusterTriggerBindingを活用
        - ref: github-push
          kind: ClusterTriggerBinding
      template:
        # 参照するTriggerTemplateを指定
        ref: build-pipeline
      interceptors:
        - github:
            # 前手順で作成したシークレットの指定
            secretRef:
              secretName: github-webhook
              secretKey: secretkey
            # GitHubのpushイベントのみでトリガー
            eventTypes:
              - push
```


```
# EventListenerの作成
$ oc apply -f trigger.yaml
triggertemplate.triggers.tekton.dev/build-pipeline created
eventlistener.triggers.tekton.dev/build-pipeline created

# EventListenerの実態であるPodが起動することを確認
$ oc get pod
NAME                                        READY  STATUS    RESTARTS   AGE
el-build-pipeline-6f84698cf5-trz2b   1/1    Running   0          17s

# リクエストを受け付けるServiceが作成されることを確認
$ oc get service
NAME                          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
el-build-pipeline      ClusterIP   172.30.141.118   <none>        8080/TCP   2m8s

# OpenShiftクラスタ外からリクエストを受け付けるためServiceをRoute経由で公開
$ oc expose service el-build-pipeline
route.route.openshift.io/el-build-pipeline exposed

$ oc get route
NAME                   HOST/PORT            PATH   SERVICES               PORT            TERMINATION   WILDCARD
el-build-pipeline      <your-endpoint>             el-build-pipeline      http-listener                 None
```

EventListenerの起動とその外部公開が完了したら、GitHubへのWebhookの設定を行います。  
レポジトリの［Settings］＞［Webhooks］から設定可能です。本例では以下のように設定します。本設定後に、レポジトリに対して何らかの変更を行うと、PipelineRunが作成され、Pipelineが実行されます。

##### GitHubへのWebhook設定内容
- Payload URL: EventListenerのRouteのホストを設定
- Content type: “application/json”を選択
- Secret: 前手順で作成した`github-webhook`シークレットの値
- Which events would you like to trigger this webhook?: “Just the push event.”を選択
- Active: チェックをつけて有効化