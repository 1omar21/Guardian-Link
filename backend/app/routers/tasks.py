import random
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends

from app.models.task import (
    TaskCreate, TaskUpdate, TaskResponse, TaskCompletionRequest,
    TaskVerificationRequest, TaskScheduleRequest, TaskStatus,
)
from app.services.firebase_service import get_firebase_service, TaskError, CHILD_DELETABLE_STATUSES
from app.middleware.auth import get_current_user

router = APIRouter()
firebase_service = get_firebase_service()

STICKER_POOL = ["🌟", "🎯", "🏆", "💎", "🎨", "🚀", "⭐", "🎪", "🎭", "🎬"]


def _require_role(current_user: dict, role: str, action: str) -> None:
    if current_user.get("role") != role:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Only {role}s can {action}"
        )


async def _notify(user_id: Optional[str], title: str, body: str, task: dict, event: str) -> None:
    """Best-effort push about a task. Never raises."""
    if not user_id:
        return
    await firebase_service.notify_user(
        user_id, title, body,
        data={"type": "task", "event": event, "task_id": task.get("id", ""), "task_title": task.get("title", "")},
    )


def _name(user: dict, fallback: str) -> str:
    return user.get("full_name") or fallback


def _task_error_to_http(e: TaskError) -> HTTPException:
    return HTTPException(status_code=e.status_code, detail=str(e))


async def _get_task_or_404(task_id: str) -> dict:
    task = await firebase_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task


@router.post("/", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    task_data: TaskCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new task (Parent only, for a child in their own family)."""
    _require_role(current_user, "parent", "create tasks")

    if not await firebase_service.is_parent_of_child(current_user["id"], task_data.assigned_to):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only assign tasks to children in your family"
        )

    try:
        task_id = await firebase_service.create_task(
            task_data=task_data.model_dump(mode="python"),
            created_by=current_user["id"]
        )
        task = await firebase_service.get_task(task_id)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create task: {str(e)}"
        )
    await _notify(
        task_data.assigned_to, f"New task: {task['title']}",
        f"Complete it to earn {task.get('reward_coins', 0)} Focus Coins", task, "created",
    )
    return TaskResponse(**task)


@router.get("/", response_model=List[TaskResponse])
async def get_tasks(
    current_user: dict = Depends(get_current_user),
    status_filter: Optional[TaskStatus] = None
):
    """
    Get tasks for the current user.

    - Child users see tasks assigned to them
    - Parent users see tasks they created
    """
    try:
        filter_value = status_filter.value if status_filter else None
        if current_user.get("role") == "child":
            tasks = await firebase_service.get_user_tasks(current_user["id"], filter_value)
        else:
            tasks = await firebase_service.get_tasks_by_creator(current_user["id"], filter_value)

        return [TaskResponse(**task) for task in tasks]
    except Exception as e:
        print(f"Get tasks error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve tasks: {str(e)}"
        )


@router.put("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    task_update: TaskUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update a task's details (Parent only, own tasks, not after completion)."""
    _require_role(current_user, "parent", "update tasks")

    task = await _get_task_or_404(task_id)
    if task.get("created_by") != current_user["id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You can only update tasks you created")
    if task.get("status") in {"completed", "verified", "deleted"}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This task can no longer be edited")

    updates = task_update.model_dump(mode="python", exclude_unset=True)
    if not updates:
        return TaskResponse(**task)

    try:
        await firebase_service.update_task(task_id, updates)
        return TaskResponse(**await firebase_service.get_task(task_id))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update task: {str(e)}"
        )


@router.post("/complete")
async def complete_task(
    completion: TaskCompletionRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Mark task as completed (Child only, own task).

    Coins are awarded exactly once, atomically with the status change.
    """
    _require_role(current_user, "child", "complete tasks")

    try:
        result = await firebase_service.complete_task_and_award(completion.task_id, current_user["id"])
    except TaskError as e:
        raise _task_error_to_http(e)
    except Exception as e:
        print(f"Complete task error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to complete task: {str(e)}"
        )

    awarded_sticker: Optional[str] = random.choice(STICKER_POOL)
    try:
        await firebase_service.add_user_sticker(current_user["id"], awarded_sticker)
        await firebase_service.set_task_sticker(completion.task_id, awarded_sticker)
    except Exception as e:
        print(f"Sticker award failed (task still completed): {e}")
        awarded_sticker = None

    updated_task = await firebase_service.get_task(completion.task_id)
    child_name = _name(current_user, "Your child")
    await firebase_service.notify_parent_of(
        current_user, f"{child_name} completed a task",
        f"\"{updated_task['title']}\" is waiting for your approval",
        data={"type": "task", "event": "completed", "task_id": completion.task_id},
    )
    return {
        **TaskResponse(**updated_task).model_dump(mode="json"),
        "coins_awarded": result["coins_awarded"],
        "new_coin_total": result["new_coin_total"],
        "sticker_awarded": awarded_sticker
    }


@router.post("/verify", response_model=TaskResponse)
async def verify_task(
    verification: TaskVerificationRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Verify a completed task (Parent only, own tasks).

    - approve: task becomes 'verified' (coins were already given on completion)
    - reject:  task becomes 'rejected' and those coins are taken back
    """
    _require_role(current_user, "parent", "verify tasks")

    try:
        await firebase_service.verify_task(
            task_id=verification.task_id,
            parent_id=current_user["id"],
            approved=verification.approved,
            feedback=verification.feedback
        )
        task = await firebase_service.get_task(verification.task_id)
    except TaskError as e:
        raise _task_error_to_http(e)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to verify task: {str(e)}"
        )
    if verification.approved:
        await _notify(task.get("assigned_to"), "Task approved! 🎉", f"\"{task['title']}\" was approved", task, "verified")
    else:
        body = f"\"{task['title']}\" was not approved"
        if verification.feedback:
            body += f": {verification.feedback}"
        await _notify(task.get("assigned_to"), "Task not approved", body, task, "rejected_by_parent")
    return TaskResponse(**task)


@router.post("/accept/{task_id}", response_model=TaskResponse)
async def accept_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Child accepts a task (own task only)."""
    _require_role(current_user, "child", "accept tasks")
    try:
        await firebase_service.accept_task(task_id, current_user["id"])
        return TaskResponse(**await firebase_service.get_task(task_id))
    except TaskError as e:
        raise _task_error_to_http(e)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept task: {str(e)}"
        )


@router.post("/reject/{task_id}", response_model=TaskResponse)
async def reject_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Child rejects a task (own task only, final decision)."""
    _require_role(current_user, "child", "reject tasks")
    try:
        await firebase_service.reject_task(task_id, current_user["id"])
        task = await firebase_service.get_task(task_id)
    except TaskError as e:
        raise _task_error_to_http(e)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to reject task: {str(e)}"
        )
    await _notify(
        task.get("created_by"), f"{_name(current_user, 'Your child')} rejected a task",
        f"\"{task['title']}\"", task, "rejected_by_child",
    )
    return TaskResponse(**task)


@router.post("/schedule/{task_id}", response_model=TaskResponse)
async def schedule_task(
    task_id: str,
    scheduled_data: TaskScheduleRequest,
    current_user: dict = Depends(get_current_user)
):
    """Child schedules a task for later (own task only)."""
    _require_role(current_user, "child", "schedule tasks")
    try:
        await firebase_service.schedule_task(task_id, current_user["id"], scheduled_data.scheduled_for)
        return TaskResponse(**await firebase_service.get_task(task_id))
    except TaskError as e:
        raise _task_error_to_http(e)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to schedule task: {str(e)}"
        )


@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Delete a task.

    - The parent who created it may delete it at any time.
    - The assigned child may delete it only before completing it (or after it
      was rejected), so a completed task can't be hidden from the parent's review.
    """
    task = await _get_task_or_404(task_id)
    is_creator = current_user["id"] == task.get("created_by")
    is_assignee = current_user["id"] == task.get("assigned_to")

    if not (is_creator or is_assignee):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to delete this task"
        )
    if task.get("status") == "deleted":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Task is already deleted")
    if is_assignee and not is_creator and task.get("status") not in CHILD_DELETABLE_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Completed tasks can't be deleted - your parent needs to review them"
        )

    try:
        await firebase_service.delete_task(task_id, current_user["id"])
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete task: {str(e)}"
        )

    if is_creator:
        await _notify(task.get("assigned_to"), "Task removed", f"\"{task['title']}\" was deleted by your parent", task, "deleted")
    else:
        await _notify(
            task.get("created_by"), f"{_name(current_user, 'Your child')} deleted a task",
            f"\"{task['title']}\"", task, "deleted",
        )
    return {"message": "Task deleted successfully"}
