class Student {
  final String name;
  final String rollNo;
  final String branch;
  final List<double> faceEmbedding;

  Student({
    required this.name,
    required this.rollNo,
    required this.branch,
    required this.faceEmbedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'rollNo': rollNo,
      'branch': branch,
      'faceEmbedding': faceEmbedding, // Our 192-dim vector
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}