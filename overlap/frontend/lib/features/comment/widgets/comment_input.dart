import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class CommentInput extends StatelessWidget {
  const CommentInput({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.focusNode,
    this.replyingToName,
    this.onCancelReply,
    this.isSubmitting = false,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final FocusNode? focusNode;
  final String? replyingToName;
  final VoidCallback? onCancelReply;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final isReplying = replyingToName != null;
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isReplying)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$replyingToName님에게 답글 작성 중',
                        style: const TextStyle(
                          color: AppColors.deepNavy,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onCancelReply,
                      child: const Text('취소'),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 200,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: isReplying
                            ? '$replyingToName님에게 답글을 남겨보세요'
                            : '댓글을 남겨보세요',
                        filled: true,
                        fillColor: AppColors.paper,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.pillRadius,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    onPressed: isSubmitting ? null : onSubmit,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.coral,
                      foregroundColor: Colors.white,
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                    tooltip: isReplying ? '답글 등록' : '댓글 등록',
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
