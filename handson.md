# ハンズオン
## 0. 確認した環境
- OpenShift: 4.8
- OpenShift Piplines: 1.5
- OpenShift GitOps: 1.2

## 1. アプリケーションを理解とOpenShiftの基本操作
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

## 2. Tetkonの基礎
### 2-1. Taskを動かす
Tektonの最小実行単位であるTaskを実行してみましょう。  
Task内には複数のStepを記述することができ、それらは順番に動作します。
Taskは同一Pod内で実行され、StepがPod内のコンテナとして動作します。

また、Taskは単純に定義でしかないため、実行するためにはTaskRunの生成が必要です。
実際にTaskを実行し、WebコンソールおよびCLI上から結果を確認しましょう。

```yaml
# multi-steps-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: multi-steps-task
spec:
  # Task内は複数のStepで記述できる。順番に実行される。
  steps:
    - name: first-output
      image: fedora:31
      command: ["echo"]
      args: ["hello first step"]
    - name: second-output
      image: fedora:32
      command: ["echo"]
      args: ["hello second step"]
    - name: third-output
      image: fedora:33
      command: ["echo"]
      args: ["hello third step"]
```

```yaml
# multi-steps-task-run.yaml
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: multi-steps-task-run
spec:
  # 利用するTaskの参照
  taskRef:
    name: multi-steps-task
```

実際に実行して、状態を確認してみよう

```
$ oc apply -f multi-steps-task.yaml
$ oc get task
$ oc apply -f multi-steps-task-run.yaml
$ oc get pod
  -> どんなPodが起動するか確認しよう。コンテナの数や出力結果
$ oc logs <pod name>　-c <container name>
  -> 出力結果の確認
$ oc get taskrun
```

実施すること
- Taskの登録
- TaskRunの登録（Taskの実行）
- 実行結果の確認
  - Taskを実行するPod
  - 出力結果(Web console & CLI)

### 2-2. Taskを動かす with params
Taskには、パラメータを設定することもできます。  
TaskRunを作成するタイミングで、パラメータを引き渡すして実行することができます。簡単な例を使ってパラメータを試してみましょう。

```yaml
# hello-my-name-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello-my-name-task
spec:
  params:
    - name: my-name
      type: string
      description: My name
      default: default-name
  steps:
    - name: output-hello-my-name
      image: fedora:latest
      command: ["echo"]
      args: ["hello $(params.my-name)"]
```

```yaml
# hello-my-name-task-run.yaml
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: hello-my-name-task-run
spec:
  params:
    - name: my-name
      value: "task param"
  # 利用するTaskの参照
  taskRef:
    name: hello-my-name-task
```

```
$ oc apply -f hello-my-name-task.yaml
$ oc get task
$ oc apply -f hello-my-name-task-run.yaml
$ oc get pod
  -> どんなPodが起動するか確認しよう。コンテナの数など
$ oc logs <pod name>
  -> 出力結果の確認
$ oc get taskrun
```

実施すること
- Taskの登録
- TaskRunの登録（Taskの実行）
- 実行結果の確認
  - Taskを実行するPod
  - ★出力結果がパラメータによって変わること

### 2-3. ClusterTask
前の手順で行ったように、Taskを独自で作成できますが、既存のTaskを活用する方法も覚えておきましょう。

CI/CDパイプライン内の処理は、Gitレポジトリからソースコードを取得することや、イメージをビルドすること、アプリケーションをデプロイすることなど、一般的な処理も多いはずです。OpenShift Pipelinesでは、インストール時にいくつかのClusterTaskを作成します。ClusterTaskは、すべてのProjectから参照できるタスクで、代表的な処理がすでに登録されています。

```
$ oc get clustertask
NAME                       AGE
buildah                    110s
buildah-v0-22-0            110s
git-cli                    104s
git-clone                  110s
git-clone-v0-22-0          110s
helm-upgrade-from-repo     104s
helm-upgrade-from-source   104s
jib-maven                  104s
kn                         110s
kn-apply                   110s
kn-apply-v0-22-0           110s
kn-v0-22-0                 110s
kubeconfig-creator         104s
maven                      104s
openshift-client           110s
openshift-client-v0-22-0   110s
pull-request               104s
s2i-dotnet                 110s
s2i-dotnet-v0-22-0         110s
s2i-go                     109s
s2i-go-v0-22-0             109s
s2i-java                   109s
s2i-java-v0-22-0           109s
s2i-nodejs                 109s
s2i-nodejs-v0-22-0         109s
s2i-perl                   109s
s2i-perl-v0-22-0           109s
s2i-php                    109s
s2i-php-v0-22-0            109s
s2i-python                 109s
s2i-python-v0-22-0         109s
s2i-ruby                   108s
s2i-ruby-v0-22-0           108s
skopeo-copy                108s
skopeo-copy-v0-22-0        108s
tkn                        104s
trigger-jenkins-job        104s
```

```
$ oc get clustertask git-clone -o yaml
Taskの中身を確認してみよう
```

実施すること
- ClusterTaskの一覧
- カタログの閲覧
- ClusterTaskの実行内容の確認

### 2-4. Pipelineを動かす
次に、Taskを束ねたPipelineについて解説します。  
Pipelineは、定義したTaskの集合体です。Pipelineを実行するために必要なパラメータの定義もできます。Pipelineは、Taskと同様に定義でしかなく、実行するためには、PipelineRunを別途作成する必要があります。シンプルなパイプラインの例を使って、各概念の関係性を整理しましょう。次のPipeline定義を使って説明します。

```yaml
# my-first-pipeline.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: my-first-pipeline
spec:
  # Pipelineに引き渡せるパラメータ定義
  params:
    - name: my-name
      type: string
    - name: my-friends
      type: array
  # Pipelineの実行内容。Taskの集合体。
  tasks:
    - name: hello-my-name
      taskRef:
        name: hello-my-name-task
      params:
        - name: my-name
          value: "$(params.my-name)"
    - name: hello-my-friends
      taskRef:
        name: hello-my-friends-task
      params:
        - name: my-friends
          value: ["$(params.my-friends[*])"]
      # hello-my-nameのTaskの実行後に行う。
      runAfter:
        - hello-my-name
---
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello-my-name-task
spec:
  params:
    - name: my-name
      type: string
      description: My name
      default: default-name
  steps:
    - name: output-hello-my-name
      image: fedora:latest
      command: ["echo"]
      args: ["hello $(params.my-name)"]
---
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello-my-friends-task
spec:
  params:
    - name: my-friends
      description: My friends name
      type: array
  steps:
    - name: output-hello-my-friends
      image: fedora:latest
      command: ["echo"]
      args: ["hello", "$(params.my-friends[*])"]
```

```yaml
# my-first-pipeline-run.yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: my-first-pipeline-run
spec:
  # 利用するPipelineの選択
  pipelineRef:
    name: my-first-pipeline
  # Pipeline実行に利用するパラメータ
  params:
    - name: my-name
      value: openshift-handson
    - name: my-friends
      value:
        - kubernetes
        - etcd
        - api-server
        - scheduler
        - controller-manager
```

Pipeline, PipelineRun, Task, TaskRunの関係性を確認しながら実行してみましょう。

<img width="1012" alt="スクリーンショット 2021-08-18 17 32 02" src="https://user-images.githubusercontent.com/733334/129866037-49cec04f-c96c-428f-ae11-427b2bf512d4.png">

```
$ oc apply -f my-first-pipeline.yaml
$ oc get pipeline
$ oc get task
$ oc apply -f my-first-pipeline-run.yaml
$ oc get pod
  -> どんなPodが起動するか確認しよう。コンテナの数など
$ oc logs <pod name>
  -> 出力結果の確認
$ oc get taskrun
$ oc get pipelinerun
```

実施すること
- TaskとPipelineの登録
- PipelineRunの登録（Pipelineの実行）
- 実行結果の確認
  - PipelineRunの確認
  - TaskRunの確認
  - パイプラインを実行するPodの確認
  - 出力結果(Web console & CLI)
- Pipeline, PipelineRun, Task, TaskRunの関係性の確認

### 2-5. Workspace
PipelineはTaskの集合体であり、Taskは独立したPodとして動作することを説明してきました。  
Pod間では、ストレージを利用しない限りデータの共有はできません。あるTask Aの結果をTask Bで利用する場合、ストレージの用意が必要となります。Tektonでは、Workspaceと呼ばれる機能で、Task間のデータを連携することができます。Workspaceには、ConfigMapやSecret、PersistentVolumeClaimなどいくつかのオプションが利用できますが、Task間でソースコードやビルド結果などのデータを連携するためにはPersistentVolumeClaimが利用できます。

次の演習で実際に利用してみます。

## 3. アプリケーションへの適用
本レポジトリのIsuumo pythonアプリに、ビルドパイプラインとArgoCDを用いたデプロイ処理を加えてみましょう。  
今回のハンズオンで実施する全体像は以下です。

<img width="1063" alt="スクリーンショット 2021-08-22 17 46 39" src="https://user-images.githubusercontent.com/733334/130348499-88ef2f1e-21bf-4769-96f2-bb143f408a5d.png">

### 3-1. リソース
- ソースコードレポジトリ: https://github.com/mosuke5/openshift-pipelines-gitops-practice
- マニフェストレポジトリ: https://github.com/mosuke5/migration-practice-for-flask-manifests
    - PythonアプリとMySQLのデプロイをKustomizeで行う

### 3-2. 事前準備
事前準備として、ふたつのProject(namespace)の作成と、production用のProjectから、Staging用のImage Streamにアクセスできるように権限付与しておきます。
`userX`は任意の値に変えてください。

```
$ oc new-project userX-production
$ oc new-project userX-staging
$ oc adm policy add-role-to-user view system:serviceaccount:userX-production:default -n userX-staging
```

### 3-3. CIパイプラインの作成
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
    
```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-pipeline
spec:
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
        - name: IMAGE
          value: $(params.image):$(params.image-tag)
        - name: DOCKERFILE
          value: "Dockerfile"
        - name: CONTEXT
          value: "$(workspaces.source.path)/$(params.context)"
      workspaces:
        - name: source
          workspace: shared-workspace
      runAfter:
        - fetch-repository
```
    
</div>
</details>

### 3-4. CIパイプラインの実行
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

### 3-5. Argo CDを用いたデプロイ
Argo CDへアクセスし、[Argo CDハンズオンの内容](https://github.com/mamoru1112/openshift-gitops-handson)を思い出しながらデプロイ設定をしましょう。本演習で実施する流れは以下のとおりです。

1. Argo CDへのログイン
2. Production用とStaging用両方のAPPLICATION（Argo CD内）を作成しましょう。
    - マニフェストレポジトリは、`main`と`staging`の２つのブランチを用意しています。`main`ブランチをProduction用、`staging`ブランチをStaging用とし、APPLICATIONを作成してみましょう。
    - デプロイ先は、事前準備で作成した２つのnamespaceにデプロイできるようにしてみましょう。`main`ブランチの変更は `userX-production`へ、`staging`ブランチの変更は `userX-staging`へデプロイしましょう。
    - 詳細設定方法は後述します。
3. Production用とStaging用、両方のAPPLICATIONをデプロイしてみましょう
    - その際、リソースの出来上がる順番に注目してみましょう
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

### 3-6. Webhookの設定
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