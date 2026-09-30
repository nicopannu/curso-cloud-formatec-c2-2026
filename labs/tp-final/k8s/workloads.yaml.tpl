apiVersion: apps/v1
kind: Deployment
metadata:
  name: pagos-api
  namespace: tp-final-ej3
  labels:
    app: pagos-api
spec:
  replicas: 2
  minReadySeconds: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: pagos-api
  template:
    metadata:
      labels:
        app: pagos-api
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: pagos-api
          image: ${PAYMENTS_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8000
          env:
            - name: APP_VERSION
              value: "${APP_VERSION}"
            - name: NOTIFICATIONS_URL
              value: http://notificaciones:8080/notify
            - name: NOTIFICATION_TIMEOUT_SECONDS
              value: "${NOTIFICATION_TIMEOUT_SECONDS}"
          resources:
            requests:
              cpu: 100m
              memory: 96Mi
            limits:
              cpu: 500m
              memory: 256Mi
          startupProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 2
            failureThreshold: 15
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: pagos-api
  namespace: tp-final-ej3
spec:
  selector:
    app: pagos-api
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notificaciones
  namespace: tp-final-ej3
  labels:
    app: notificaciones
spec:
  replicas: 2
  minReadySeconds: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: notificaciones
  template:
    metadata:
      labels:
        app: notificaciones
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: notificaciones
          image: ${NOTIFICATIONS_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: APP_VERSION
              value: "${APP_VERSION}"
            - name: NOTIFICATION_DELAY_SECONDS
              value: "0"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 192Mi
          startupProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 2
            failureThreshold: 15
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: notificaciones
  namespace: tp-final-ej3
spec:
  selector:
    app: notificaciones
  ports:
    - name: http
      port: 8080
      targetPort: http
