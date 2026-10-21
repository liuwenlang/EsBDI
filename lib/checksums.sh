#!/usr/bin/env bash
# 默认安装包的 SHA-512。换成本机文件或别的版本时跳过校验。

expected_sha512() {
  local name
  name=$(basename "${1%%\?*}")
  case "${name}" in
    hadoop-2.7.7.tar.gz)
      printf '%s\n' "17c8917211dd4c25f78bf60130a390f9e273b0149737094e45f4ae5c917b1174b97eb90818c5df068e607835120126281bcc07514f38bd7fd3cb8e9d3db1bdde"
      ;;
    zookeeper-3.4.14.tar.gz)
      printf '%s\n' "b2e03d95f8cf18b97a46e2f53871cef5a5da9d5d80b97009375aed7fb35368c440ca944c7e8b64efabbc065f6fb98bb86239f7c1491f0490efc71876d5a7f424"
      ;;
    spark-2.4.7-bin-hadoop2.7.tgz)
      printf '%s\n' "0f5455672045f6110b030ce343c049855b7ba86c0ecb5e39a075ff9d093c7f648da55ded12e72ffe65d84c32dcd5418a6d764f2d6295a3f894a4286cc80ef478"
      ;;
    hbase-2.2.4-bin.tar.gz)
      printf '%s\n' "214fcc1ca7d4e70bffdaa41fe9e55a3a5c492ead7e02680d901481d124bd9ec279035f05b1f88ebd4bcdba67c8ecdf9f093cefcaecd8e211b7ec842149517a8d"
      ;;
    kafka_2.11-2.4.1.tgz)
      printf '%s\n' "63d8844df751e5f1cb792f52d58709cc50a7b1b8c5d94e3f8d9c815c818ca95070656913d5772302bbc818dae9e67e4a5d715789654ee87c714cfd2f88b2a24f"
      ;;
    apache-flume-1.9.0-bin.tar.gz)
      printf '%s\n' "a989c50389c779dd7554c98bdba687fa982d6079d308c85ac210d3e523aa54b4b7452f38fe30d9acdac327080fe316d604b5efb0f3943cbacb4839fb2261f535"
      ;;
    *)
      return 1
      ;;
  esac
}
