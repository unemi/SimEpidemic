---

# simepidemic HTTP Server版仕様書 ver. 0
著者：畝見達夫、作成：令和2年9月1日、編集：9月4日

このドキュメントでは、感染シミュレータ SimEpidemic の HTTP server 版における、起動オプション、クライアントとの間のプロトコル等の仕様について述べる。

### サーバプロセスの起動と終了
サーバソフトウェアは macOS 10.14 以降で動作するコマンドライン・アプリケーションである。
UNIX の標準的な起動方法によりバックグラウンドで実行することを想定している。
終了については特別な方法は用意されていないので、TERM または KILL シグナルにより強制終了させる。
実行モジュールの標準的なファイル名は `simepidemic` である。

	# simepidemic -port 8001 -JSONOptions 3 &

### HTTP 要求と応答
クライアント側からの要求にサーバが応答する。
クライアントはエンドユーザに対してGUIなどの操作・表示手段を提供するものであり、
javascript 等で書かれたコードにより制御されるWEBブラウザ等を想定する。
多くのブラウザでは、HTTPプロトコルに規定されるいくつかのヘッダが自動的に構成されるため、
以下ではプロトコルの詳細は省略し、ブラウザ上で動くプログラムの開発に必要な情報だけを記述する。

[パラメータ設定](#SetParams)や[実行制御](#Control)など、応答としてデータを返す必要のない要求に
対しては、サーバは `text/plain` 型のエラー等の情報を示すデータを返す。
特に以下の説明で記述がない場合データは `OK` のみである。 

### パラメータ値の取得
#### 要求 `GET /getParams`
* `options=`<[JSONフォーマットオプション](#JSONForm)>
<!--* <[パラメータ名](#ParamNames)>`=1`
このオプションが添えられた場合は、指定されたパラメータの情報を応答する。
同時に複数のパラメータ名を指定できる。このオプションが１つも含まれない場合は、すべてのパラメータの情報が返る。
-->
* `save=`<ファイル名>
このオプションが添えられた場合は、ダウンロード形式で応答する。
	
	JSON の辞書形式のデータを myParams.json に保存する。

		<form method="get" action="getParams">
		<input type="hidden" name="options" value=3 />
		<input type="text" name="save" value="myParams" />
		<input type="submit" value="Save"/>
		</form>
		

#### 応答 `Content-type: application/json`
 [パラメータ名](#ParamNames) をキー、設定するパラメータ値を値とする辞書形式。

### <a name=SetParams></a>パラメータ値の設定
#### 要求 `POST /setParams`
* Payload: `Content-type: application/json`
 [パラメータ名](#ParamNames) をキー、設定するパラメータ値を値とする辞書形式。

	ユーザが指定したファイルからパラメータを読み込み設定する。
	
		<form method="post" action="setParams">
		<input type="file" accept="application/json"/>
		<input type="submit" value="Load"/>
		</form>

* Payload: `Content-type: application/x-www-form-urlencoded`
 [パラメータ名](#ParamNames) = パラメータ値の羅列。

	初期人口と世界の広さを設定する。
		
		<form method="post" action="setParams">
		<table>
		<tr><td align="right">人口</td>
			<td><input type="number" name="populationSize"/></td></tr>
		<tr><td align="right">世界の大きさ</td>
			<td><input type="number" name="worldSize"/></td></tr>
		</table><br/>
		<input type="submit" value="Set"/>
		</form>

### <a name=ParamNames></a>パラメータ名と型
分布は最小値、最大値、最頻値の３つの数の組で表現され、
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

### <a name=Control></a>実行の制御
シミュレーションの実行の開始 `start`、停止 `stop`、1ステップ進む `step` のコマンド１つを、
要求行に入れた `GET` メソッドによりクライアントからサーバへ指示する。

サーバからの応答として、問題がなければ OK がテキストとして返る。
		
	<form method="get" target="result">
	<input type="submit" value="Start" formaction="start"/>
	<input type="submit" value="Step" formaction="step"/>
	<input type="submit" value="Stop" formaction="stop"/>
	</form>
	結果: <iframe name="result" width=100 height=20></iframe>

### 実行の監視と結果の取得
現在のサーバ側での実行の状況あるいは実行開始からの履歴を取得する。
<div style="font-size:8pt">

| 指標名 | 日本語名 | 型 | 単位 | 範囲 | 履歴 | 日ごと | 累積 |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| `step` | ステップ数 | 整数 | - | > 0 | |
| `days` | 経過日数 | 実数 | 日 | > 0 | |
| `suceptible` | 未感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |
| `asymptomatic` | 無症状感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |
| `symptomatic` | 発症感染者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |
| `recovered` | 快復者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |
| `died` | 死亡者数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |
| `quarantine` | 隔離数 | 整数 | 人 | < 初期人口 | ◯ | ◯ |

### <a name=JSONForm></a>JSONフォーマットオプション

* option として与える整数の意味  
1 ... pretty print ... 入れ子の深さに応じて段つけを行う。  
2 ... sorted keys ... 辞書内の要素をキー文字列のアルファベット順に並び替える。  
4 ... allow fragments  
8 ... without escaping slashes  
ビットごと論理和を取ることで複数のオプションを同時に設定する。  
既定値は0。
