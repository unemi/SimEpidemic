<style type="text/css">
.myForm {font-family:Courier;font-weight:bold;background:#F8F8F8;
 border:solid 1pt #ddd;border-radius:2pt;padding:2pt}
</style>

---
# simepidemic HTTP Server版仕様書 ver. 0 *α*
著者：畝見達夫，作成：令和2年9月1日，編集：9月5日

このドキュメントでは，感染シミュレータ SimEpidemic の HTTP server 版における，起動オプション，クライアントとの間のプロトコル等の仕様について述べる。

[toc]

## サーバプロセスの起動と終了
サーバソフトウェアは macOS 10.14 以降で動作するコマンドライン・アプリケーションである。
UNIX の標準的な起動方法によりバックグラウンドで実行することを想定している。
終了については特別な方法は用意されていないので，TERM または KILL シグナルにより強制終了させる。
実行モジュールの標準的なファイル名は `simepidemic` である。

コマンドオプションは以下のとおり。

* <span class=myForm>-p, --port *ポート番号*</span> : HTTP サーバのポート番号を指定する。既定値は 8000。
* <span class=myForm>-f, --format *n*</span> :
[JSON フォーマットオプション](#JSONForm)の既定値を指定する。
このオプションを指定しない場合の既定値は 0。
<a name=ComOptDirectory></a>
* <span class=myForm>-d, --directory *パス*</span> : HTML などのファイルが格納されているディレクトリのパス。
絶対パスあるいは、`simepidemic` コマンドを起動したときの作業ディレクトリからの相対パス。
既定値はコマンド起動時の作業ディレクトリ。

例：ポート番号 8001番を使用し、JSONのフォーマットに段つけと辞書キーのソートを指定して、
バックグラウンドで実行を開始する。

	$ simepidemic -p 8001 -f 3 &

## HTTP 要求と応答
クライアント側からの要求にサーバが応答する。
クライアントはエンドユーザに対してGUIなどの操作・表示手段を提供するものであり，
javascript 等で書かれたコードにより制御されるWEBブラウザ等を想定する。
多くのブラウザでは，HTTPプロトコルに規定されるいくつかのヘッダが自動的に構成されるため，
以下ではプロトコルの詳細は省略し，ブラウザ上で動くプログラムの開発に必要な情報だけを記述する。

[パラメータ設定](#SetParams)や[実行制御](#Control)など，応答としてデータを返す必要のない要求に
対しては，サーバは `text/plain` 型のエラー等の情報を示すデータを返す。
特に以下の説明で記述がない場合データは `OK` のみである。 

シミュレータへの要求コマンドではなく、`.html`，`.css`，`.js`，`.jpg`
などのファイル拡張子を伴うパスが指定された場合は．
該当するファイルがホスト側に存在すれば，通常の WEB サーバと同様その内容を応答する。
サーバのトップディレクトリ `/` の `GET` 要求に対しては、`index.html` ファイルが存在すれば，
その内容を応答する。
これらのファイルは，既定値では `simepidemic`
コマンドが起動された状態での作業ディレクトリ下にあるものと仮定される。
ディレクトリの位置は [コマンドライン・オプション `-d`](#ComOptDirectory) で指定可能である。

## パラメータ値の取得
### 要求 `GET /getParams`
<!--* <[パラメータ名](#ParamNames)>`=1`
このオプションが添えられた場合は，指定されたパラメータの情報を応答する。
同時に複数のパラメータ名を指定できる。このオプションが１つも含まれない場合は，すべてのパラメータの情報が返る。
-->
* <span class=myForm>save=\<*ファイル名*\></span> *省略可*
このオプションが添えられた場合は，ダウンロード形式で応答する。
* <span class=myForm>format=\<[*JSONフォーマットオプション*](#JSONForm)\></span> *省略可*
	
例：JSON の辞書形式のデータを myParams.json に保存する。

	<form method="get" action="getParams" target="saveResult">
	<input type="hidden" name="format" value=0>
	<input type="text" name="save" value="myParams">
	<input type="submit" value="保存">
	</form>
	応答: <iframe name="saveResult" height=20></iframe>
		

### 応答 `Content-type: application/json`
 [パラメータ名](#ParamNames) をキー，設定するパラメータ値を値とする辞書形式。

<a name=SetParams></a>
## パラメータ値の設定
### 要求 `POST /setParams`
#### 積載情報: `Content-type: application/json`
 [パラメータ名](#ParamNames) をキー，設定するパラメータ値を値とする辞書形式。

例：ユーザが指定したファイルからパラメータを読み込み設定する。
	
	<form method="post" action="setParams"
	  enctype="multipart/form-data" target="loadParamResult">
	<input type="file" accept="application/json">
	<input type="submit" value="読み込む">
	</form>
	応答: <iframe name="loadParamResult"></iframe>

#### 積載情報: `Content-type: application/x-www-form-urlencoded`
 [パラメータ名](#ParamNames) と パラメータ値 の組みの集合。

例：初期人口と世界の広さを設定する。
	
	<form method="post" action="setParams">
	<table>
	<tr><td align="right">人口</td>
		<td><input type="number" name="populationSize"></td></tr>
	<tr><td align="right">世界の大きさ</td>
		<td><input type="number" name="worldSize"></td></tr>
	</table><br/>
	<input type="submit" value="設定"/>
	</form>

<a name=ParamNames></a>
## パラメータ名と型
分布は最小値，最大値，最頻値の３つの数の組で表現され，
JSON形式では３つの要素からなる配列で表現される。
<div style="font-size:8pt">

| パラメータ名 | 日本語名 | 分類 | 型 | 単位 | 既定値 | 範囲 | 備考 |
| ---- | ---- | ---- | ---- | ---- | ---: | ---- | ---- |
| `populationSize` | 初期人口 |  世界 | 整数 | 人 | 10,000 | 100 - 任意 |
| `worldSize` | 世界の大きさ | 世界 | 整数 | 距離単位 | 360 | 10 - 任意 | 一辺の長さ |
| `mesh` | メッシュ | 世界 | 整数 | - | 18 | 1 - 999 | 縦横の各分割数 |
| `stepsPerDay` | 1日当たりステップ数 |  世界 | 整数 | ステップ | 4 | 1 - 999 |
| `initialInfected` | 初期状態での感染者数 |  世界 | 整数 | 人 | 4 | 1 - 999 |
| `infectionProberbility` | 感染確率 | 発症機序 | 実数 | % | 50., | 0., - 100. |
| `infectionDistance` | 感染距離 | 発症機序 | 実数 | 距離単位 | 4., | 1., - 20. |
| `incubation` | 潜伏期間 | 発症機序 | 分布 | 日 | [1.,14.,5.] |
| `fatality` | 発症から死亡まで | 発症機序 | 分布 | 日 | [4.,20.,16.] |
| `recovery` | 快復開始まで | 発症機序 | 分布 | 日 | [4.,40.,10.] |
| `immunity` | 免疫有効期間 | 発症機序 | 分布 | 日 | [30.,360.,180.] |
| `distancingStrength` | 社会的距離の強さ | 対策 | 実数 | % | 50. | 0. - 100. |
| `distancingObedience` | 社会的距離協力率 | 対策 | 実数 | % | 20. | 0. - 100. |
| `mobilityFrequency` | 移動頻度 | 対策 | 実数 | ‰ | 50. | 0. - 100. |
| `mobilityDistance` | 移動距離 | 対策 | 分布 | % | [10.,80.,30.] | | 世界の大きさとの比 |
| `contactTracing` | 接触者追跡 | 対策 | 実数 | % | 20. | 0. - 100. | 捕捉率 |
| `testDelay` | 検査の遅れ | 検査 | 実数 | 日 | 1. | 0. - 10. |
| `testProcess` | 処理期間 | 検査 | 実数 | 日 | 1. | 0. - 10. | 検査から判明まで
| `testInterval` | 検査間隔 | 検査 | 実数 | 日 | 2. | 0. - 10. | 次の検査まで
| `testSensitivity` | 感度 | 検査 | 実数 | % | 70. | 0. - 100. |
| `testSpecificity` | 特異度 | 検査 | 実数 | % | 99.8 | 0. - 100. |
| `subjectAsymptomatic` | 疑症状検査対象者 | 検査 | 実数 | % | 1. | 0. - 100. |
| `subjectSymptomatic` | 有症状検査対象者 | 検査 | 実数 | % | 99. | 0., - 100. |

</div>

<a name=Control></a>
## 実行の制御
シミュレーションの実行の
開始 `start`，停止 `stop`，1ステップ進む `step` ，および世界の初期化 `reset` のコマンド１つを，
要求行に入れた `GET` メソッドによりクライアントからサーバへ指示する。
サーバからの応答として，問題がなければ OK がテキストとして返る。

例：開始，一歩，停止、初期化の4つのボタン
		
	<form method="get" target="result">
	<input type="submit" value="開始" formaction="start">
	<input type="submit" value="一歩" formaction="step">
	<input type="submit" value="停止" formaction="stop">
	<input type="submit" value="初期化" formaction="reset">
	</form>
	応答: <iframe name="result" width=100 height=20></iframe>

## 実行の監視と結果の取得
現在のサーバ側での実行の状況あるいは実行開始からの履歴を取得する。
### 要求 `GET /getIndexes`
* <span class="myForm">names=[<*統計指標名1*>, <*統計指標名2*>, ...]</span>
*または* <span class="myForm"><*統計指標名*>=1</span> *いずれか必須* :
取得したい[統計指標名](#IndexNames)を指定する。後者の形式は複数含めても良い。
* <span class="myForm">fromStep=<*n*></span> *または*
<span class="myForm">fromDay=<*n*></span> *省略可* :
`fromStep` と `fromDay` が共に指定された場合は `fromDay` を優先。
可能なら *n* ステップ(あるいは日)から現在までの履歴を返す。
共に省略された場合，および，指標が履歴に対応しない場合は現在の値だけを返す。
*n* が負の場合は現在から |*n* | ステップ(あるいは日)前からの履歴を返す。
* <span class="myForm">window=<*n*></span> *省略可* :
日ごとの値の移動平均の窓幅の日数。
*n* が 0 または，この指定が省略された場合は，現在数または累積を返す。
* <span class=myForm>format=\<[*JSONフォーマットオプション*](#JSONForm)\></span> *省略可*

### 応答 `Content-type: application/json`
 [統計指標名](#IndexNames) をキー，指標値を値とする辞書形式。
 
 例：経過日数と各健康状態の現在の人数を取得し、iframe の内容として格納する。
 
	<form method="get" action="/getIndexes" target="currentIndexes">
	<input type="hidden" name="day" value=1>
	<input type="hidden" name="susceptible" value=1>
	<input type="hidden" name="asymptomatic" value=1>
	<input type="hidden" name="symptomatic" value=1>
	<input type="hidden" name="recovered" value=1>
	<input type="hidden" name="died" value=1>
	<input type="submit" value="現在の人口構成">
	</form>
	<iframe name="currentIndexes"></iframe>

### 要求 `GET /getDistribution`
* <span class="myForm">names=[<*統計指標名1*>, <*統計指標名2*>, ...]</span>
*または* <span class="myForm"><*統計指標名*>=1</span> *いずれか必須* :
取得したい[統計指標名](#IndexNames)を指定する。後者の形式は複数含めても良い。
* <span class=myForm>format=\<[*JSONフォーマットオプション*](#JSONForm)\></span> *省略可*

### 応答 `Content-type: application/json`
 [統計指標名](#IndexNames) をキー，指標値のベクトルを値とする辞書形式。
 各ベクトルの第1要素は横軸の最小値，第2要素以降に刻みごとの値が入る。

<a name=IndexNames></a>
## 統計指標名と型
シミュレーション過程で得られる統計指標には，ステップあるいは日ごとに変化する数値情報と，
過程開始以来の指標の分布を表す分布情報がある。

### 数値情報
指標の性質により，履歴，日ごと，現在数，累積に利用可能性の違いがある。
<div style="font-size:8pt">

| 統計指標名 | 日本語名 | 型 | 単位 | 範囲 | 履歴 | 日ごと | 現在数 | 累積 |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| `isRunning` | 実行中 | 真偽値 | - | true/false |||||
| `step` | ステップ数 | 整数 | - | > 0 |||◯||
| `days` | 経過日数 | 実数 | 日 | > 0 |||◯||
| `susceptible` | 未感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `asymptomatic` | 無症状感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `symptomatic` | 発症感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `recovered` | 快復者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `died` | 死亡者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `quarantineAsymptomatic` | 無症状隔離数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `quarantineSymptomatic` | 有症状隔離数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `testAsSymptom` | 発症者検査数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
| `testAsContact` | 接触者検査数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
| `testAsSuspected` | 擬症状者検査数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
| `testPositive` | 陽性者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
| `testNegative` | 陰性者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
| `testPositiveRate` | 陽性率 | 実数 | % | 0 - 100 | ◯ | ◯ | | |

</div>

### 分布情報
全数累積統計による。
横軸の各値に該当した個体がそれまでに合計何人であったを示すベクトルで表現される。
<div style="font-size:8pt">

| 統計指標名 | 日本語名 | 横軸 | 縦軸 | 備考 |
| ---- | ---- | ---- | ---- | ---- |
| `incubasionPeriod` | 潜伏期間 | 日 | 人 | 発症者の内，感染から発症まで |
| `recoveryPeriod` | 快復期間 | 日 | 人 | 発症から快復まで |
| `fatalPeriod` | 生存期間 | 日 | 人 | 発症から死亡まで |
| `infects` | 感染数 | 人 | 人 | 感染させた人数 |
| `contacts` | 接触者数 | 人日 | 人 | 未実装|

</div>

<a name=JSONForm></a>
## JSONフォーマットオプション

* option として与える整数の意味  
1 ... pretty print ... 入れ子の深さに応じて段つけを行う。  
2 ... sorted keys ... 辞書内の要素をキー文字列のアルファベット順に並び替える。  
4 ... allow fragments  
8 ... without escaping slashes  
ビットごと論理和を取ることで複数のオプションを同時に設定する。  
既定値は0。

---
