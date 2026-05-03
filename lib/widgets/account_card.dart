import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../utils/app_theme.dart';

class AccountCard extends StatelessWidget {
  final Account account;
  final Proxy? proxy;
  final bool isSelected;
  final bool batchMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AccountCard({
    super.key,
    required this.account,
    this.proxy,
    required this.isSelected,
    required this.batchMode,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleStatus,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = account.status == 'done';

    return Dismissible(
      key: Key(account.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('Xóa tài khoản?', style: TextStyle(color: Colors.white)),
            content: Text(
              account.email,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.secondary.withAlpha(40) : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: AppColors.secondary, width: 1.5) : null,
          ),
          child: Row(
            children: [
              // Batch checkbox or status button
              if (batchMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                    size: 22,
                  ),
                )
              else
                GestureDetector(
                  onTap: onToggleStatus,
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isDone
                          ? AppColors.done.withAlpha(30)
                          : AppColors.todo.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDone ? Icons.check : Icons.hourglass_empty,
                      color: isDone ? AppColors.done : AppColors.todo,
                      size: 18,
                    ),
                  ),
                ),

              // Account info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.email,
                      style: TextStyle(
                        color: isDone ? AppColors.textSecondary : Colors.white,
                        fontSize: 14,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (account.group != null) ...[
                          Container(
                            margin: const EdgeInsets.only(right: 6, top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              account.group!,
                              style: const TextStyle(
                                  color: AppColors.secondary, fontSize: 10),
                            ),
                          ),
                        ],
                        if (proxy != null) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.done.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.vpn_lock,
                                    size: 10, color: AppColors.done),
                                const SizedBox(width: 3),
                                Text(
                                  proxy!.displayLabel,
                                  style: const TextStyle(
                                      color: AppColors.done, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              if (!batchMode)
                PopupMenuButton<String>(
                  color: AppColors.surfaceVariant,
                  icon: const Icon(Icons.more_vert,
                      color: AppColors.textSecondary, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'status') onToggleStatus();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'status',
                      child: Row(children: [
                        Icon(
                          isDone ? Icons.hourglass_empty : Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDone ? 'Đặt lại chờ' : 'Đánh dấu xong',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Chỉnh sửa', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete, size: 16, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Xóa', style: TextStyle(color: AppColors.error)),
                      ]),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
