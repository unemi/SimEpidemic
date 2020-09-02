---

# simepidemic HTTP Server版仕様書 ver. 0
著者：畝見達夫、作成：令和2年9月1日、編集：9月2日

このドキュメントでは、感染シミュレータ SimEpidemic の HTTP server 版における、起動オプション、クライアントとの間のプロトコル等の仕様について述べる。

## パラメータ値の取得
### 要求
* Method: `GET`, Last component of URI: `getParams`
* Optional: `options=`<[JSONフォーマットオプション](#JSONForm)>
* Optional: <パラメータ名>`=1`
このオプションが添えられた場合は、指定されたパラメータの情報を応答する。
同時に複数のパラメータ名を指定できる。このオプションが１つも含まれない場合は、すべてのパラメータの情報が返る。
* Optional: `save=<filename>`
このオプションが添えられた場合は、ダウンロード形式で応答する。
	
*	ex. `GET /getParams?options=3&save=myParams HTTP/1.1`  

### 応答
* `Content-type: application/json`

## パラメータ値の設定
### 要求
* Method: `POST`, Last component of URI: `setParams`
	
*	ex. `POST /setParams HTTP/1.1`  

### 応答
* `Content-type: text/plain`

## 実行の制御
## 実行の監視
## 実行結果の取得
## <a name=#JSONForm></a>JSONフォーマットオプション
	option として与える整数の意味  
	1 ... pretty print ... 入れ子の深さに応じて段つけを行う。  
	2 ... sorted keys ... 辞書内の要素をキー文字列のアルファベット順に並び替える。  
	4 ... allow fragments  
	8 ... without escaping slashes  
	ビットごと論理和を取ることで複数のオプションを同時に設定する。  
	既定値は0。
