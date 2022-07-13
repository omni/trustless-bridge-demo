FROM golang:1.18.3 as build

WORKDIR /app

COPY go.* ./
RUN go mod download

COPY . .

RUN mkdir -p out/light_client out/light_client_chain out/amb && \
    go build -o ./out/light_client ./cmd/light_client/... && \
    go build -o ./out/amb ./cmd/amb/...

FROM ubuntu:20.04

WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates && update-ca-certificates

COPY --from=build /app/out/ ./

EXPOSE 3333

ENTRYPOINT ["./light_client/worker"]
