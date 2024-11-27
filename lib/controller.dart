import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class QuizController extends GetxController {
  // Constantes y Temporizadores
  final int initialTime = 15;
  Timer? timer;

  // Estado del juego
  RxInt currentQuestionIndex = 0.obs;
  RxString currentTeam = "A".obs;
  RxInt scoreA = 0.obs;
  RxInt scoreB = 0.obs;
  RxInt timeLeft = 15.obs;
  RxBool isPaused = true.obs;
  RxBool isWaitingResponse = false.obs;
  RxBool isQuestionsLoaded = false.obs;
  RxString selectedAnswer = "".obs;

  // Bluetooth
  RxBool isScanning = false.obs;
  RxList<BluetoothDevice> bondedDevices =
      <BluetoothDevice>[].obs; // Emparejados
  RxList<BluetoothDiscoveryResult> discoveredDevices =
      <BluetoothDiscoveryResult>[].obs; // Escaneados
  BluetoothConnection? connection;
  RxBool isConnected = false.obs;

  // Preguntas
  List<dynamic> questions = [];

  @override
  void onInit() {
    super.onInit();
    requestPermissions();
    loadQuestions();
    initializeBondedDevices(); // Cargar dispositivos emparejados
  }

  // ----------------------------
  // Gestión de Preguntas
  // ----------------------------
  Future<void> loadQuestions() async {
    try {
      final String response =
          await rootBundle.loadString('assets/questions.json');
      final data = json.decode(response);
      questions = data;
      isQuestionsLoaded.value = true;
      log("Preguntas cargadas correctamente.");
    } catch (e) {
      log("Error al cargar preguntas: $e");
      isQuestionsLoaded.value = false;
      Get.snackbar("Error", "No se pudo cargar las preguntas.");
    }
  }

  void resetGame() {
    currentQuestionIndex.value = 0;
    scoreA.value = 0;
    scoreB.value = 0;
    currentTeam.value = "A";
    timeLeft.value = initialTime;
    isPaused.value = true;
    isWaitingResponse.value = false;
    selectedAnswer.value = "";
    log("Juego reiniciado.");
  }

  void nextQuestion({Function? onGameFinished}) {
    if (currentQuestionIndex.value < questions.length - 1) {
      currentQuestionIndex.value++;
      currentTeam.value = currentTeam.value == "A" ? "B" : "A";
      timeLeft.value = initialTime;
      isWaitingResponse.value = false;
      selectedAnswer.value = "";
      log("Pasando a la siguiente pregunta.");
    } else {
      timer?.cancel();
      isPaused.value = true;
      log("Juego terminado.");
      if (onGameFinished != null) onGameFinished();
    }
  }

  Future<void> checkAnswer(
      String answer, Function onShowModal, Function onGameFinished) async {
    if (isPaused.value) return;

    selectedAnswer.value = answer;
    isPaused.value = true;
    isWaitingResponse.value = true;

    onShowModal();

    final isCorrect = await sendDataToArduinoAndValidate(answer);

    if (isCorrect) {
      currentTeam.value == "A" ? scoreA.value++ : scoreB.value++;
      log("Respuesta correcta.");
    } else {
      log("Respuesta incorrecta.");
    }

    isPaused.value = false;
    isWaitingResponse.value = false;

    nextQuestion(onGameFinished: onGameFinished);
  }

  // ----------------------------
  // Temporizador
  // ----------------------------
  void startTimer(Function onTimeUpdate, Function onTimeUp) {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeLeft.value > 0 && !isPaused.value) {
        timeLeft.value--;
        onTimeUpdate();
      } else if (timeLeft.value == 0) {
        onTimeUp();
        nextQuestion();
      }
    });
  }

  void togglePause() {
    if (!isConnected.value) {
      Get.snackbar("Advertencia",
          "Debe conectarse a un dispositivo Bluetooth para iniciar el juego.");
      return;
    }
    isPaused.value = !isPaused.value;
    if (isPaused.value) {
      timer?.cancel();
      log("Juego pausado.");
    } else {
      log("Juego iniciado.");
    }
  }

  // ----------------------------
  // Bluetooth
  // ----------------------------
  Future<void> requestPermissions() async {
    final status = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (status[Permission.bluetooth]!.isGranted &&
        status[Permission.bluetoothScan]!.isGranted &&
        status[Permission.bluetoothConnect]!.isGranted) {
      log("Permisos concedidos.");
    } else {
      Get.snackbar("Permisos", "Se requieren permisos de Bluetooth.");
    }
  }

  void initializeBondedDevices() async {
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      bondedDevices.value = devices;
      log("Dispositivos emparejados: ${bondedDevices.map((d) => d.name).toList()}");
    } catch (e) {
      log("Error al obtener dispositivos emparejados: $e");
      Get.snackbar(
          "Error", "No se pudieron cargar los dispositivos emparejados.");
    }
  }

  void startDiscovery() {
    isScanning.value = true;
    discoveredDevices.clear();

    FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      if (!discoveredDevices
          .any((device) => device.device.address == result.device.address)) {
        discoveredDevices.add(result);
      }
    }).onDone(() {
      isScanning.value = false;
      log("Escaneo completado.");
    });
  }

  void connectToHC05(String address) async {
    try {
      connection = await BluetoothConnection.toAddress(address);
      isConnected.value = true;
      log("Conectado al dispositivo Bluetooth.");

      connection!.input!.listen((data) {
        log("Datos recibidos: ${utf8.decode(data)}");
      }).onDone(() {
        isConnected.value = false;
        log("Conexión cerrada.");
      });
    } catch (e) {
      log("Error al conectar: $e");
      Get.snackbar("Error", "No se pudo conectar al dispositivo.");
    }
  }

  Future<bool> sendDataToArduinoAndValidate(String answer) async {
    if (connection == null || !connection!.isConnected) {
      log("No hay conexión activa con el Arduino.");
      return false;
    }

    try {
      connection!.output.add(utf8.encode(answer + "\r\n"));
      await connection!.output.allSent;

      final completer = Completer<bool>();
      connection!.input!.listen((data) {
        String response = utf8.decode(data).trim();
        log("Respuesta del Arduino: $response");

        if (response.toLowerCase() == "true") {
          completer.complete(true);
        } else if (response.toLowerCase() == "false") {
          completer.complete(false);
        }
      }).onError((error) {
        log("Error: $error");
        completer.complete(false);
      });

      return completer.future;
    } catch (e) {
      log("Error al enviar datos: $e");
      return false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    connection?.finish();
    super.dispose();
    log("Recursos liberados.");
  }
}
