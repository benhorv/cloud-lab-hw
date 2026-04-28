#set document(title: "OCR Felhőalkalmazás — Fejlesztői dokumentáció", author: "Horváth Benedek")
#set text(font: "Times New Roman", size: 12pt, lang: "hu")
#set par(justify: true, leading: 0.9em, spacing: 1em)
#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set heading(numbering: "1.")
#show heading: it => { set text(weight: "bold"); set block(below: 1em, above: 1.5em); it }
#show figure.where(kind: raw): set figure(supplement: [Kódrészlet])
#show figure.where(kind: image): set figure(supplement: [ábra])
#show figure: it => {
  let num = counter(figure.where(kind: it.kind)).display(it.numbering)
  if it.kind == raw {
    align(left, it.body)
  } else {
    it.body
  }
  if it.has("caption") {
    v(8pt)
    align(center, text(size: 11pt, style: "italic")[#num. #lower(it.supplement): #it.caption.body])
  }
}
#show raw.where(block: true): box.with(
  fill: luma(245),
  inset: 10pt,
  radius: 3pt,
  stroke: 0.5pt + black,
  width: 100%,
)

// --- Címlap ---
#page(header: none, footer: none)[
  #align(center)[
    #v(3cm)
    #v(1fr)
    #text(size: 12pt)[Felhők hálózati szolgáltatásai laboratórium \ BMEVITMMB11]
    #v(1em)
    #text(size: 22pt, weight: "bold")[OCR alapú felhőalkalmazás]
    #v(0.5em)
    #text(size: 16pt)[Fejlesztői dokumentáció]
    #v(1em)
    #text(size: 14pt)[Horváth Benedek \ D86EP7]
    #v(1fr)
    #text(size: 12pt)[Budapest, 2026]
  ]
]

#outline(title: "Tartalomjegyzék", indent: auto, depth: 2)
#pagebreak()

= Bevezetés

A házi feladat célja egy OCR (optikai karakterfelismerés) alapú webszolgáltatás megvalósítása felhős ökoszisztémában. Jelen dokumentáció első verziója a kialakított CI/CD környezetet ismerteti.

= CI/CD környezet

== Architektúra áttekintés

A CI/CD pipeline a következő folyamatot valósítja meg:

+ A fejlesztő push-ol a `master` branch-re
+ A GitHub Actions workflow buildeli a Docker image-et
+ Az image feltöltésre kerül a Docker Hub-ra
+ A workflow frissíti a Helm `values.yaml` fájlt az új image tag-gel (commit SHA)
+ Az ArgoCD észleli a változást és automatikusan deployolja az új verziót a K3s klaszterbe

== Futási környezet

A fejlesztés és futtatás egy otthoni Fedora szerveren történik, SSH kapcsolaton keresztül.

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 8pt,
  [OS], [Fedora Server],
  [Kubernetes], [K3s Fedora miatt],
  [CD], [ArgoCD],
  [CI], [GitHub Actions],
  [Container registry], [Docker Hub],
  [Package], [Helm],
)

== K3s telepítése

A laboroktól eltérően minikube helyett K3s-t választottam. A K3s egy lightweight Kubernetes disztribúció, amelyet edge és szerver környezetekbe terveztek. Natívan fut Fedoran, nem igényel VM-et vagy Docker-in-Docker megoldást, és alacsony erőforrásigényű.

#figure(
  ```bash
  curl -sfL https://get.k3s.io | sh -
  ```,
  caption: [K3s telepítése],
)

#figure(image("assets/image-2.png", width: 80%), caption: [K3s klaszter állapota])

== ArgoCD telepítése

A laborról ismerős ArgoCD-t választottam. Az ArgoCD olyan CD eszköz, amely a Git repóban tárolt manifesteket automatikusan szinkronizálja a klaszterrel. A telepítés így nézett ki:

#figure(
  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl patch svc argocd-server -n argocd \
    -p '{"spec": {"type": "NodePort"}}'
  ```,
  caption: [ArgoCD telepítése a K3s klaszterre],
)

#figure(image("assets/image-3.png", width: 80%), caption: [ArgoCD podok állapota])

== GitHub repó és projekt struktúra

A repositorí felépítése megegyezik a laborokéval. Az app almappa tartalmazza az alkalmazást és a docker imaget felépítő Dockerfilet. A helm mappa pedig az erőforrások létrehozásáért felel.

#figure(image("assets/image-4.png", width: 60%), caption: [Repó struktúra])

== Dockerfile

A laborról ismerős Flask alkalmazást használom placeholder-ként, amely majd az OCR funkciókat valósítja meg.

#figure(
  ```python
  from flask import Flask

  app = Flask(__name__)

  @app.route("/health")
  def health():
      return "OK"

  @app.route("/")
  def index():
      return "Hello Cloud Lab OCR App!"

  if __name__ == '__main__':
      app.run(host="0.0.0.0", port=5000)
  ```,
  caption: [Flask alkalmazás (app/app.py)],
)

A Dockerfile alapján épül fel a Python appot tartalmazó minimális konténer. 

#figure(
  ```dockerfile
  FROM python:3.12-slim
  RUN pip install flask
  WORKDIR /app
  COPY app.py .
  CMD ["python", "-u", "app.py"]
  ```,
  caption: [Dockerfile (app/Dockerfile)],
)

== Helm templates

A Kubernetes erőforrások leírásához Helm chart-ot készítettem. A `deployment.yaml` definiálja a futtatandó pod-ot, megadja az image nevét és verzióját (a `values.yaml`-ből), a konténer portját, valamint readiness és liveness probe-okat a `/health` végponton, ezek biztosítják, hogy a Kubernetes automatikusan újraindítsa a pod-ot, ha az alkalmazás nem válaszol.

#figure(
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: ocr-app
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: ocr-app
    template:
      metadata:
        labels:
          app: ocr-app
      spec:
        containers:
          - name: ocr-app
            image: benhorv/ocr-app:{{ .Values.env.APP_VERSION }}
            ports:
              - name: http
                containerPort: 5000
            readinessProbe:
              httpGet:
                path: /health
                port: 5000
            livenessProbe:
              httpGet:
                path: /health
                port: 5000
  ```,
  caption: [Kubernetes Deployment (helm/templates/deployment.yaml)],
)

A `service.yaml` hálózati végpontot biztosít a pod számára. Egyszerűség kedvéért NodePort típusú, így kívülről is látszódik, és ki tudom rakni Cloudflare Tunnellel (erről később lesz szó). Ez a megoldás most egyszerűbb a K3s miatt is.

#figure(
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: ocr-app
  spec:
    type: NodePort
    ports:
      - port: 5000
        targetPort: http
        protocol: TCP
        name: http
    selector:
      app: ocr-app
  ```,
  caption: [Kubernetes Service (helm/templates/service.yaml)],
)

A Helm `values.yaml` fájlban az `APP_VERSION` értéket a GitHub Actions workflow minden push után automatikusan frissíti a commit SHA-ra, így az ArgoCD mindig a legfrissebb image-et deployolja.

== GitHub Actions CI pipeline

A `master` branch-re történő push hatására a workflow:
- Buildeli a Docker image-et (commit SHA tag-gel)
- Push-olja a Docker Hub-ra
- Frissíti a Helm `values.yaml`-t az új tag-gel

#figure(
  ```yaml
  name: CD
  on:
    push:
      branches: [master]
  env:
    DOCKERHUB_USERNAME: ${{ secrets.DOCKER_USERNAME }}
    DOCKERHUB_KEY: ${{ secrets.DOCKER_KEY }}
    IMAGE_NAME: ocr-app
  jobs:
    build-and-deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Login to Docker Hub
          uses: docker/login-action@v3
          with:
            username: ${{ env.DOCKERHUB_USERNAME }}
            password: ${{ env.DOCKERHUB_KEY }}
        - name: Build Docker image
          run: cd app && docker build -t
            ${{ env.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .
        - name: Push Docker image
          run: docker push
            ${{ env.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        - name: Update Helm values.yaml
          run: |
            cd helm
            sed -i 's|APP_VERSION:.*|APP_VERSION: '${{ github.sha }}'|' values.yaml
            git config --global user.name 'GitHub Actions'
            git config --global user.email 'actions@github.com'
            git add values.yaml
            git commit -m "Update image tag to ${{ github.sha }}"
            git push
  ```,
  caption: [GitHub Actions workflow (cd.yml)],
)

#figure(image("assets/image-5.png", width: 80%), caption: [GitHub Actions sikeres futás])

#figure(image("assets/image-6.png", width: 80%), caption: [Docker Hub image])

Fent látható, hogy a CD fájl alapján a megfelelő folyamatok lefutottak, lefutott az action GitHubon, és feltöltődött az image DockerHubra, amit majd az ArgoCD húz le.

== GitHub Secrets

A Docker Hub credentials titkosított GitHub Secrets-ként vannak tárolva:
- `DOCKER_USERNAME`: Docker Hub felhasználónév
- `DOCKER_KEY`: Docker Hub access token

#figure(image("assets/image-7.png", width: 80%), caption: [GitHub Secrets beállítás])

== ArgoCD alkalmazás

Az ArgoCD a következő beállításokkal figyeli a repót:
- *Sync Policy*: Automatic
- *Prune Resources*: enable
- *Self Heal*: enable

#figure(image("assets/image-9.png", width: 80%), caption: [ArgoCD alkalmazás állapota])

Látszik, hogy az ArgoCD megfelelő beállítás után sikeresen lehúzta a megfelelő imaget, és elindult az alkalmazás.

== Publikus elérés

Nem a házi feladat szerves része, de a környezetből adódóan kihasználom, hogy már futnak szolgáltatások a szerveremen egy publikus DNS címen. Ezek a szolgálatások Cloudflare Tunnel-en keresztül érhetők el, így ez már be volt állítva, egyszerűen hozzá tudtam adni az OCR appot. A tunnel a K3s NodePort szolgáltatásra (`localhost:31719`) irányít, így az alkalmazás a `https://ocr.bedelab.hu` címen érhető el külső hálózatról is, anélkül hogy a szerveren portot kellene nyitni a tűzfalon. Így biztonságosan, HTTPS-en keresztül elérhető, anélkül, hogy SSH-val kéne ügyeskednem, és ellenőrizhető is a feladat. :)

#figure(image("assets/image-10.png", width: 80%), caption: [Cloudflare Tunnel konfiguráció])

== Működés ellenőrzése

Az alkalmazás a K3s klaszterben fut, NodePort-on érhető el lokálisan, és Cloudflare Tunnel-en keresztül publikusan a `https://ocr.bedelab.hu` címen.

#figure(image("assets/image-11.png", width: 80%), caption: [Az alkalmazás a böngészőben])

= Weboldal és OCR detektálás

== Architektúra

A második részfeladatban a placeholder Flask alkalmazást egy valódi OCR webszolgáltatással váltottam fel. A rendszer két külön konténerből áll, amelyek egy Kafka üzenetsoron keresztül kommunikálnak egymással. Ez a megközelítés megfelel a felhős mikroszolgáltatás-elveknek, a webapp és az OCR egymástól függetlenül skálázható és futtatható.

Így néz ki egy szekvencia:

+ A user feltölti a képet
+ A `web` konténer elmenti a képet a megosztott PVC-re (`/data/<uuid>/`), majd üzenetet küld a Kafka `ocr-jobs` topicba
+ A `worker` konténer megkapja az üzenetet, lefuttatja az OCR-t, és az eredményt beírja a `meta.json` fájlba
+ A user a képre kattintva láthatja az annotált verziót, amin a detektált szavak jelölve vannak

== Stack

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 8pt,
  [OCR], [Tesseract (pytesseract)],
  [Képfeldolgozás], [Pillow],
  [Üzenetsor], [Kafka],
  [Tárolás], [Kubernetes PVC (K3s lokális tárhely)],
  [Webszerver], [Flask],
)

A Tesseract mellett döntöttem, mivel konténerben futtatható, nem igényel külső API-t. A Kafka a laboron megismert megoldás, ezért választottam. Lehet kicsit előre dolgoztam a Kafkával, de a 3. feladatrészhez jól jön, hogy már megvan.

== Projektstruktúra

Az `app` mappa két alkönyvtárra bővült:

#figure(
  ```
  app/
    web/          # Flask webalkalmazás
      app.py
      Dockerfile
      templates/
        index.html
    worker/       # OCR feldolgozó
      worker.py
      Dockerfile
  ```,
  caption: [Frissített projekt struktúra],
)

== Adatszerkezet

Minden feltöltött kép egy saját könyvtárban tárolódik a PVC-n:

#figure(
  ```
  /data/
    <uuid>/
      image<ext>    // az eredeti feltöltött kép
      meta.json     // leírás + OCR eredmények
  ```,
  caption: [Tárolási struktúra a PVC-n],
)

A `meta.json` felépítése:

#figure(
  ```json
  {
    "description": "Példa leírás",
    "text": "Detektált szöveg egy sorban",
    "ext": ".png",
    "status": "done",
    "words": [
      {"text": "Szó", "x": 10, "y": 20, "w": 50, "h": 15}
    ]
  }
  ```,
  caption: [meta.json adatszerkezet],
)

== Web konténer (app/web)

A Flask alkalmazás három végpontot valósít meg:

- `GET /`: korábbi feltöltések listája leírással és detektált szöveggel
- `POST /upload`: kép mentése a PVC-re, üzenet küldése a Kafka `ocr-jobs` topicba, átirányítás
- `GET /image/<id>`: annotált kép megjelenítése/kiszolgálása, ezzel dolgozik a Pillow is

#figure(
  ```dockerfile
  FROM python:3.12-slim
  RUN pip install flask pillow kafka-python
  WORKDIR /app
  COPY app.py .
  COPY templates/ templates/
  CMD ["python", "-u", "app.py"]
  ```,
  caption: [Web Dockerfile (app/web/Dockerfile)],
)

== Worker konténer (app/worker)

A worker egy Kafka consumer, amely folyamatosan figyeli az `ocr-jobs` topicot. Minden üzenet érkezésekor beolvassa a képet a PVC-ről, lefuttatja a Tesseract OCR-t, majd visszaírja az eredményt a `meta.json` fájlba.

#figure(
  ```dockerfile
  FROM python:3.12-slim
  RUN apt-get update && apt-get install -y tesseract-ocr \
      && rm -rf /var/lib/apt/lists/*
  RUN pip install pytesseract pillow kafka-python
  WORKDIR /app
  COPY worker.py .
  CMD ["python", "-u", "worker.py"]
  ```,
  caption: [Worker Dockerfile (app/worker/Dockerfile)],
)

== Kafka

A Kafka a `default` névtérben fut egy egyszerű Deployment-ként, a laboron megismert `bashj79/kafka-kraft` image alapján. A `KAFKA_ADVERTISED_LISTENERS` környezeti változóval a K8s service hostname-re van konfigurálva, hogy más névterekből is elérhető legyen.

#figure(
  ```yaml
  env:
    - name: KAFKA_ADVERTISED_LISTENERS
      value: "PLAINTEXT://kafka.default.svc.cluster.local:9092"
  ```,
  caption: [Kafka advertised listener beállítása],
)

== Helm templates

A `deployment.yaml` két deploymentet definiál (`ocr-web` és `ocr-worker`), mindkettő ugyanazt a PVC-t mountolja `/data` alá. A `values.yaml` külön verziótageket tárol a két image-hez, amelyeket a CI pipeline frissít.

#figure(
  ```yaml
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: ocr-data
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
  ```,
  caption: [PersistentVolumeClaim (helm/templates/pvc.yaml)],
)

== GitHub Actions CI pipeline

A CI pipeline kiegészült a két image buildelésével és pusholásával, valamint a `values.yaml` mindkét verziótagjének frissítésével.

#figure(
  ```yaml
  - name: Build and push web image
    run: |
      docker build -t ${{ env.DOCKERHUB_USERNAME }}/ocr-web:${{ github.sha }} app/web
      docker push ${{ env.DOCKERHUB_USERNAME }}/ocr-web:${{ github.sha }}

  - name: Build and push worker image
    run: |
      docker build -t ${{ env.DOCKERHUB_USERNAME }}/ocr-worker:${{ github.sha }} app/worker
      docker push ${{ env.DOCKERHUB_USERNAME }}/ocr-worker:${{ github.sha }}
  ```,
  caption: [Frissített CI pipeline (cd.yml)],
)

#figure(image("assets/image-12.png", width: 80%), caption: [GitHub Actions-ben web és worker image buildelése])

#figure(image("assets/image-13.png", width: 80%), caption: [Docker Hub ocr-web és ocr-worker image-ek])

== Működés ellenőrzése

Az alkalmazás podjai a `kubectl get pods -n ocr-app` paranccsal ellenőrizhetők.

#figure(image("assets/image-14.png", width: 80%), caption: [Futó podok állapota])

#figure(image("assets/image-15.png", width: 80%), caption: [A weboldal feltöltési formmal és OCR eredménnyel])

#figure(image("assets/image-16.png", width: 80%), caption: [Annotált kép a detektált szövegekkel])
