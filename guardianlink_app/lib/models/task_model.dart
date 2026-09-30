class Task {
  final String id;
  final String title;
  final String description;
  final String assignedTo;
  final String createdBy;
  final String status; // 'pending', 'in_progress', 'completed', 'verified'
  final String priority; // 'low', 'medium', 'high'
  final int rewardCoins;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? completedAt;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.createdBy,
    required this.status,
    this.priority = 'medium',
    this.rewardCoins = 10,
    this.dueDate,
    required this.createdAt,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedTo: json['assigned_to'] ?? '',
      createdBy: json['created_by'] ?? '',
      status: json['status'] ?? 'pending',
      priority: json['priority'] ?? 'medium',
      rewardCoins: json['reward_coins'] ?? 10,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      createdAt: DateTime.parse(json['created_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assigned_to': assignedTo,
      'created_by': createdBy,
      'status': status,
      'priority': priority,
      'reward_coins': rewardCoins,
      'due_date': dueDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  bool get isCompleted => status == 'completed' || status == 'verified';
  bool get isPending => status == 'pending';
}
