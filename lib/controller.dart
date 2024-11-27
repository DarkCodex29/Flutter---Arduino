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
    initializeBondedDevices(); // Carga dispositivos emparejados
  }

  // ----------------------------
  // Gestión de Preguntas
  // ----------------------------
  Future<void> loadQuestions() async {
    try {
      // Leer el archivo JSON desde los assets
      final String response =
          await rootBundle.loadString('assets/questions.json');
      final data = json.decode(response);

      // Asignar las preguntas al atributo 'questions'
      questions = data;
      isQuestionsLoaded.value = true;
      log("Preguntas cargadas correctamente desde el archivo JSON.");
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
      log("Pasando a la siguiente pregunta. Turno del equipo ${currentTeam.value}");
    } else {
      timer?.cancel();
      if (onGameFinished != null) onGameFinished();
      log("Juego terminado.");
    }
  }

  void checkAnswer(String answer, Function onShowModal) {
    if (isPaused.value) return;

    selectedAnswer.value = answer;
    isWaitingResponse.value = true;

    // Comparar la respuesta seleccionada con la correcta
    bool isCorrect = questions[currentQuestionIndex.value]["answer"] == answer;
    if (isCorrect) {
      currentTeam.value == "A" ? scoreA.value++ : scoreB.value++;
      log("Respuesta correcta para el equipo ${currentTeam.value}.");
    } else {
      log("Respuesta incorrecta para el equipo ${currentTeam.value}.");
    }

    sendDataToHC05(isCorrect ? "Correcto" : "Incorrecto");
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
      log("Intento de iniciar sin conexión Bluetooth.");
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
  // Bluetooth - Emparejados y Escaneo
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
      log("Permisos de Bluetooth concedidos.");
    } else {
      log("Faltan permisos de Bluetooth.");
      Get.snackbar("Permisos",
          "Debe conceder los permisos de Bluetooth para continuar.");
    }
  }

  // Cargar dispositivos emparejados
  void initializeBondedDevices() async {
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      if (devices.isNotEmpty) {
        bondedDevices.value = devices;
        log("Dispositivos emparejados: ${bondedDevices.map((d) => d.name).toList()}");
      } else {
        log("No hay dispositivos emparejados.");
        Get.snackbar(
            "Bluetooth", "No se encontraron dispositivos emparejados.");
      }
    } catch (e) {
      log("Error al obtener dispositivos emparejados: $e");
      Get.snackbar(
          "Error", "No se pudieron cargar los dispositivos emparejados.");
    }
  }

  // Escanear dispositivos cercanos
  void startDiscovery() {
    isScanning.value = true;
    discoveredDevices.clear();

    FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      // Evitar duplicados
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
      log("Conectado al HC-05 ($address)");

      connection!.input!.listen((data) {
        log("Datos recibidos: ${utf8.decode(data)}");
      }).onDone(() {
        isConnected.value = false;
        log("Conexión cerrada.");
      });
    } catch (e) {
      log("Error al conectar al HC-05: $e");
      Get.snackbar("Error", "No se pudo conectar al HC-05.");
    }
  }

  void sendDataToHC05(String data) {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(utf8.encode(data + "\r\n"));
      log("Datos enviados al HC-05: $data");
    } else {
      log("No hay conexión activa con el HC-05");
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
