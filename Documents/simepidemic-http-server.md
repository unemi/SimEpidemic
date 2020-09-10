<style type="text/css">
.myForm {font-family:Courier;font-weight:bold;background:#F8F8F8;
 border:solid 1pt #ddd;border-radius:2pt;padding:2pt}
</style>

---
# simepidemic HTTP Server版仕様書 ver. 0 *α*
著者：畝見達夫，作成：令和2年9月1日，編集：9月9日

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
* <span class=myForm>-d, --directory *パス*</span> :
HTML などのファイルが格納されているディレクトリのパス。
`/` で始まる絶対パスあるいは、`simepidemic` コマンドを起動したときの作業ディレクトリからの相対パス。
既定値はコマンド起動時の作業ディレクトリ。
* <span class=myForm>--version</span> : ソフトウェアのバージョンを表す文字列を表示し停止する。

ポートを他のプロセスが使用していたり，サーバプロセスの停止から数秒以内に再起動した場合などでポートの
確保に失敗すると，即座に停止し終了コード 2 を返す。

例：ポート番号 8001番を使用し、JSONのフォーマットに段つけと辞書キーのソートを指定して、
バックグラウンドで実行を開始する。

	$ simepidemic -p 8001 -f 3 &

サーバプロセスを起動したマシンで Webブラウザから
<span class=myForm> http://localhost:*ポート番号*/</span> へアクセスすると，
`index.html `があれば，その内容が描画される。

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
ただし，動画や音声などのためのストリーミングによる発信は実装されておらず，
これらのファイルを指定した場合は 415 (Unsupported Media Type) エラーになる。
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
シミュレーションを実行するときに使われるパラメータ値を設定する。
パラメータは，*世界*，*発症機序*，*対策*，*検査* の4種類に分類される。
詳細は，[パラメータ名と型](#ParamNames)を参照。
このうち世界に分類されるパラメータは，シミュレーション開始前でなければ適用できない。
シミュレーションの途中で世界パラメータの設定を行うと，新たに指定された値は予約として記録され，
次に[世界を初期化](#Control)したときに反映される。
### 要求 `POST /setParams`
#### 積載情報: `Content-type: multipart/form-data`
 [パラメータ名](#ParamNames) をキー，設定するパラメータ値を値とする辞書形式の JSON データのパートを含む。

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
開始要求には問い合わせ情報として <span class=myForm>stopAt=<*n*></span> を付けることができ，
実行日数が整数 *n* に到達した時点で停止する。この指定がなければ `stop` 要求があるか，
あるいは，感染者が 0 になるまで実行が継続される。

1つのシミュレーション環境に対応する「世界」は，アクセス元の IP アドレス1つにつき1つである。
つまり，1つのマシンから複数の世界を操作することはできない。
また，他のマシンからアクセスすれば，独立した世界が用意される。
さらに，無用な世界の増加を防ぐため，最後の操作または動作から 20分が経過した時点で，
世界を閉じる。その後に同じ IP アドレスからの要求があった場合は，新たに世界が用意される。
> この仕様は便宜的に用意されたもので，様々な意味で好ましくない。ユーザIDと世界IDを用意し，
> 共有や階層構造の組織化を含めたアクセスコントロール機能を装備すべきであろう。
> また，無用な実行継続の放置を抑止するため，最長実行時間などもサーバ側で設定可能とすべきである。

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
取得したい数値情報の[統計指標名](#IndexNames)を指定する。後者の形式は複数含めても良い。
* <span class="myForm">fromStep=<*n*></span> *または*
<span class="myForm">fromDay=<*n*></span> *省略可* :
`fromStep` と `fromDay` が共に指定された場合は `fromDay` を優先。
可能なら *n* ステップ（あるいは日）から現在までの履歴を返す。
共に省略された場合，指定されたステップ（あるいは日）が実行済みのシミュレーション期間より先の場合，
および，指標が履歴に対応しない場合は現在の値だけを返す。
*n* が負の場合は現在から |*n* | ステップ（あるいは日）前からの履歴を返す。
履歴は、データが日ごとの場合は日ごと、現在数と累積についてはステップごとの数値の配列になる。
ただし，ステップ数（あるいは日数）が 1,280 を超えると，内部の記録データが2ステップ（あるいは日）
ずつの平均値に置き換えられ，記録される数値の数が半分の 640 に短縮される。
この操作は記録データの数が 1,280 を超えるたびに実行される。
* <span class="myForm">window=<*n*></span> *省略可* :日ごとの値の移動平均の窓幅の日数。
*n* が 0 または，この指定が省略された場合は，現在数または累積を返す。
*n > 1 について未実装。*
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
取得したい分布情報の[統計指標名](#IndexNames)を指定する。後者の形式は複数含めても良い。
* <span class=myForm>format=\<[*JSONフォーマットオプション*](#JSONForm)\></span> *省略可*

### 応答 `Content-type: application/json`
 [統計指標名](#IndexNames) をキー，指標値のベクトルを値とする辞書形式。
 各ベクトルの第1要素は横軸の最小値，第2要素以降に刻みごとの値が入る。
 例えば `{"recoveryPeriod":[4,2,5,10,6,3,0,1]}` は，快復期間の分布が
 4日2人，5日5人，6日10人，7日6人，8日3人，9日0人，10日1人であることを表す。
 
 例：潜伏期間と快復期間の分布を取得し、iframe の内容として格納する。

	<form method="get" action="/getDistribution" target="distribution">
	<input type="hidden" name="incubasionPeriod" value=1>
	<input type="hidden" name="recoveryPeriod" value=1>
	<input type="submit" value="日数の分布">
	</form>
	<iframe name="distribution"></iframe>

<a name=IndexNames></a>
## 統計指標名と型
シミュレーション過程で得られる統計指標には，ステップあるいは日ごとに変化する数値情報と，
過程開始以来の指標の分布を表す分布情報がある。

### 数値情報
指標の性質により，履歴，日ごと，現在数，累積に利用可能性の違いがある。
<div style="font-size:8pt">

| 統計指標名 | 日本語名 | 型 | 単位 | 範囲 | 履歴 | 日ごと | 現在数 | 累積 |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| `isRunning` | 実行中 | 真偽値 | - | true/false |||◯||
| `step` | ステップ数 | 整数 | - | > 0 |||◯||
| `days` | 経過日数 | 実数 | 日 | > 0 |||◯||
| `susceptible` | 未感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `asymptomatic` | 無症状感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `symptomatic` | 発症感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `recovered` | 快復者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `died` | 死亡者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `quarantineAsymptomatic` | 無症状隔離数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `quarantineSymptomatic` | 有症状隔離数 | 整数 | 人 | < 初期人口 | ◯ | ◯ | ◯ ||
| `tests` | 検査数 | 整数 | 人 | < 初期人口 | ◯ | ◯ || ◯ |
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

<a name=Population></a>
## 個体の位置と健康状態の取得
現在の全個体の位置と健康状態の一覧を取得する。
### 要求 `GET /getPopulation`
### 応答 `Content-type: application/json`
個体の XY座標と健康状態の種類を表す計3つの整数からなる配列を個体数分含む配列の形式で表現される。
XおよびYの値は，世界の大きさを 10,000 としたときの座標を表す整数。
健康状態は 0=未感染，1=無症状感染，2=発症，3=快復，4=死亡。
世界は*フィールド*，*病院*，*墓地* の3つの領域に分かれており，
フィールドは一辺の長さが 10,000 の正方形で，その右側に病院と墓地が配置される。
病院と墓地は，縦がフィールドの半分の長さの長方形で，病院が上，墓地が下に隣接した配置である。
病院と墓地の中の X座標は 10,000 以上，病院内の Y 座標は 5,000 未満，墓地内のY 座標は 5,000 以上である。
さらに移動中の個体についは，上の3つの整数に加え，目標位置の XY 座標を表す2つの整数と，
移動モードを表す1つの整数が加わった計6個の整数の配列で表現される。
移動モードの値の意味は，0=フィールド内移動，1=入院，2=フィールから埋葬，3=病院から埋葬，4=退院
である。

例：現在の全個体の位置と健康状態を iframe に取り込む。

	<form method="get" action="getPopulation" target="populationData">
	<input type="submit" value="フィールド個体情報">
	</form>
	<iframe name="populationData"></iframe>

人口の大きさに比例してデータサイズが増加する。
サーバからは deflate 形式で圧縮されたデータが送られてくるが，
ほとんどのブラウザでは受け取った時点で圧縮を解いてくれるので，
クライアント側のプログラムは解凍処理を行う必要はない。
サーバから送出されるデータのサイズは人口1万人の場合，48〜58kバイト程度である。

<a name=Scenario></a>
## シナリオの設定
統計指標の変化を調べる条件とパラメータ値変更等の操作の列で表現される *シナリオ* を設定する。
シナリオが実行されるとパラメータ値が変化する。シミュレーション開始時点でのパラメータ値は，
シナリオを設定した時点でのパラメータ値が初期値として記録され，
世界の初期化が行われると，パラメータ値もその記録された値に戻る。
### 要求 `POST /setScenario`
#### 積載情報: `Content-type: multipart/form-data`
シナリオを表現する JSON データを含む。

例：ユーザが指定したファイルからパラメータを読み込み設定する。

	<form method="post" action="setScenario"
		 enctype="multipart/form-data" target="loadScenario">
	<input type="file" name="upload" accept="application/json">
	<input type="submit" value="読み込む">
	</form>
	応答: <iframe name="loadScenario" height=20></iframe>

#### 積載情報: `Content-type: x-www-form-urlencoded`
* <span class=myForm>scenario=<*JSONデータ*></span> *必須* :
設定したいシナリオを表現する JSON データの文字列を指定する。

### シナリオのデータ表現
シナリオは複数の，*条件*，*追加感染者数*，または，*操作*を要素とする配列である。

* **条件** : 配列または文字列型で表現される。配列の第1要素は整数，第2要素は文字列である。
条件式は文字列で表現され，条件用の統計指標の値と定数値の大小比較を基本述語とする。
比較演算子は `==`, `!=`, `>`, `>=`, `<`, `<=` の6種類である。
それらを論理和 `OR` または論理積 `AND` で結合し，さらにそれらを入れ子にした式の文字列で表現することもできる。
入れ子の結合関係を明確にするため，式を `()` で囲むことができる。
指標名や演算子の間は空白で区切る。
配列の第1要素の整数は，条件が満たされた場合のシナリオ内の移動先を示す。
整数の値は配列内の0から始まるインデックス番号である。
単独の文字列の場合は，条件が満足されると，配列内のその次の要素に制御が移る。
いずれの場合も，条件が満足されるまでシミュレーションが実行される。
* **追加感染者数** : 整数で表現される。この要素に実行が渡ると，
現在の世界にいる未感染者から指定された人数をランダムに選び，無症状感染者に変更する。
* **操作** : 配列で表現される。操作可能なパラメータの名前と新たな値の組。
操作可能なパラメータは，パラメータと型の表にある「世界」以外に分類され，実数または整数を型とする
つぎの13のパラメータである。
`infectionProberbility`, `infectionDistance`, `distancingStrength`, `distancingObedience`, `mobilityFrequency`, `contactTracing`, `testDelay`, `testProcess`, `testInterval`, `testSensitivity`, `testSpecificity`, `subjectAsymptomatic`, `subjectSymptomatic`。

追加感染者数または操作の要素が配列内で連続して存在する場合は，
それらの先頭に制御が移った時点で一気にそれらすべての要素が実行される。
制御がシナリオの最後に達した場合は，それ以上シナリオは実行されない。
世界が初期化された場合は，シナリオの制御は先頭に戻る。

アプリ版の SimEpidemic バージョン 1.6.2 以降では，シナリオを JSON 形式でも保存・読込が可能になっているので、
そのシナリオパネルで編集した内容をファイルに保存し利用することが可能である。
SimEpidemic のシナリオパネルで JSON 形式で保存するには，保存先のファイル名の拡張子を `json` にする。

### 条件用の統計指標
シナリオの条件として使える統計指標は以下の表のとおり。
<div style="font-size:8pt">

| 統計指標名 | 日本語名 | 単位 | 備考 |
| ---- | ---- | ---- | ---- |
| `days` |  経過日数 | 日 | |
| `susceptible` | 未感染者数 | 人 | 現在数 |
| `infected` | 感染者数 | 人 | 無症状者と発症者の現在数の合計 |
| `symptomatic` | 発症者数 | 人 | 現在数 |
| `recovered` | 快復者数 | 人 | 免疫保持者の現在数 |
| `died` | 死亡者数 | 人 | 現在数＝累積 |
| `quarantine` | 隔離数 | 人 | 現在数 |
| `dailyInfection` | 当日の新規感染者数 | 人 | 実数。検査とは無関係 |
| `dailySymptomatic` | 当日の新規発症者数 | 人 |  |
| `dailyRecovery` | 当日の新規快復者数 | 人 |  |
| `dailyDeath` | 当日の死亡者数 | 人 |  |
| `weeklyPositive` | 週間陽性数 | 人 | 過去7日間の陽性判明件数の合計 |
| `weeklyPositiveRate` | 週間陽性率 | 率 0.0〜1.0 | 過去7日間の陽性判明数を検査数で割った値 |

</div>

<a name=JSONForm></a>
## JSONフォーマットオプション

* option として与える整数の意味  
1 ... pretty print ... 入れ子の深さに応じて段つけを行う。  
2 ... sorted keys ... 辞書内の要素をキー文字列のアルファベット順に並び替える。  
4 ... allow fragments ... 配列，辞書以外の要素のみのデータも許可する。このシステムでは無意味。  
8 ... without escaping slashes  
ビットごと論理和を取ることで複数のオプションを同時に設定する。  
既定値は0。

---
