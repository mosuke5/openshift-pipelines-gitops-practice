# Tekton基礎
## 1. Taskを動かす
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

## 2. Taskを動かす with params
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

## 3. ClusterTask
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

## 4. Pipelineを動かす
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

## 5. Workspace
PipelineはTaskの集合体であり、Taskは独立したPodとして動作することを説明してきました。  
Pod間では、ストレージを利用しない限りデータの共有はできません。あるTask Aの結果をTask Bで利用する場合、ストレージの用意が必要となります。Tektonでは、Workspaceと呼ばれる機能で、Task間のデータを連携することができます。Workspaceには、ConfigMapやSecret、PersistentVolumeClaimなどいくつかのオプションが利用できますが、Task間でソースコードやビルド結果などのデータを連携するためにはPersistentVolumeClaimが利用できます。

次の演習で実際に利用してみます。
