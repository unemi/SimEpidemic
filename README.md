# SimEpidemic
Individual-based Epidemic Simulator (2020-21)

- As a part of [project](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/) by Tatsuo Unemi, under cooperation with Saki Nawata and Masaaki Miyashita.
- Supported by Cabinet Secretariat of Japanese Government.

This is an individual-based simulator to help understanding the dynamics of epidemic, spread of infectous disease, mainly targetting SARS-CoV-2.

This repository includes two different versions, macOS application and HTTP server. Both run on macOS 11, and 12. The project file SimEpidemic.xcodeproj is tuned for universal binary runnable on both Intel x86_64 and Apple Sillicon arm64 CPUs.

You can find more detail of the project at [http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/)
and the technical detail in Japanese at  [http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/simepidemic-docs.html](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/simepidemic-docs.html).

## How to install the HTTP server version
The HTTP server version is also in a form of universal binary.
If the execution module "simepidemic" is immediately killed by zsh just after the invokation; please try to "archive" the product, export it into a local folder, then copy the product module "simepidemic" under Products/use/local/bin to the target server machine.

## Subdirectories
- SimEpidemic ... macOS application.
- SimEpidemicSV ... HTTP server's main part.
- Sample ... sample parameter files.
- simepiWorld, simepiBackend ... another version of HTTP server under construction.

&copy; Tatsuo Unemi, 2020-21, All rights reserved.

---
