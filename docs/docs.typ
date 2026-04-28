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
