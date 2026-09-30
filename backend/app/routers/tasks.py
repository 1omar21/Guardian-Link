from fastapi import APIRouter, HTTPException, status, Depends
from app.models.task import (
    TaskCreate, TaskUpdate, TaskResponse, TaskCompletionRequest, TaskVerificationRequest
)
from app.services.firebase_service import FirebaseService
from app.middleware.auth import get_current_user
from typing import List

router = APIRouter()
firebase_service = FirebaseService()


@router.post("/", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    task_data: TaskCreate,
    current_user: dict = Depends(get_current_user)
):
    """
    Create a new task (Parent only).
    
    - Parents can assign tasks to their children
    - Tasks include reward coins for gamification
    """
    if current_user.get("role") != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only parents can create tasks"
        )
    
    try:
        task_id = await firebase_service.create_task(
            task_data=task_data.dict(),
            created_by=current_user["id"]
        )
        
        task = await firebase_service.get_task(task_id)
        return TaskResponse(**task)
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create task: {str(e)}"
        )


@router.get("/", response_model=List[TaskResponse])
async def get_tasks(
    current_user: dict = Depends(get_current_user),
    status_filter: str | None = None
):
    """
    Get tasks for the current user.
    
    - Child users see tasks assigned to them
    - Parent users see tasks they created
    """
    try:
        if current_user.get("role") == "child":
            # Child sees tasks assigned to them
            tasks = await firebase_service.get_user_tasks(
                user_id=current_user["id"],
                status_filter=status_filter
            )
        else:
            # Parent sees tasks they created
            tasks = await firebase_service.get_tasks_by_creator(
                creator_id=current_user["id"],
                status_filter=status_filter
            )
        
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
    """
    Update a task (Parent only).
    """
    if current_user.get("role") != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only parents can update tasks"
        )
    
    try:
        await firebase_service.update_task(task_id, task_update.dict(exclude_unset=True))
        task = await firebase_service.get_task(task_id)
        return TaskResponse(**task)
        
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
    Mark task as completed (Child only).
    
    - Child marks task as complete
    - Coins awarded immediately
    """
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can complete tasks"
        )
    
    try:
        # Get task details first to get reward coins
        task = await firebase_service.get_task(completion.task_id)
        
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found"
            )
        
        # Mark task as completed
        await firebase_service.complete_task(completion.task_id)
        
        # Award coins to child
        reward_coins = task.get('reward_coins', 0)
        new_total = await firebase_service.update_user_coins(
            current_user["id"],
            reward_coins
        )
        
        # Award sticker (simple emoji-based system)
        import random
        sticker_pool = ["🌟", "🎯", "🏆", "💎", "🎨", "🚀", "⭐", "🎪", "🎭", "🎬"]
        awarded_sticker = random.choice(sticker_pool)
        
        # Add sticker to user's collection
        try:
            await firebase_service.add_user_sticker(current_user["id"], awarded_sticker)
        except:
            awarded_sticker = None  # Don't fail task completion if sticker fails
        
        print(f"✅ Task completed! Awarded {reward_coins} coins. New total: {new_total}")
        if awarded_sticker:
            print(f"🎁 Awarded sticker: {awarded_sticker}")
        
        # Return updated task
        updated_task = await firebase_service.get_task(completion.task_id)
        return {
            **TaskResponse(**updated_task).dict(),
            "coins_awarded": reward_coins,
            "new_coin_total": new_total,
            "sticker_awarded": awarded_sticker
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Complete task error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to complete task: {str(e)}"
        )


@router.post("/verify", response_model=TaskResponse)
async def verify_task(
    verification: TaskVerificationRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Verify task completion (Parent only).
    
    - Parent approves or rejects task completion
    - If approved, Focus Coins are awarded to child
    """
    if current_user.get("role") != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only parents can verify tasks"
        )
    
    try:
        await firebase_service.verify_task(
            task_id=verification.task_id,
            approved=verification.approved,
            feedback=verification.feedback
        )
        
        task = await firebase_service.get_task(verification.task_id)
        return TaskResponse(**task)
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to verify task: {str(e)}"
        )
@router.post("/accept/{task_id}")
async def accept_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Child accepts a task."""
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can accept tasks"
        )
    
    try:
        await firebase_service.accept_task(task_id)
        task = await firebase_service.get_task(task_id)
        return TaskResponse(**task)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept task: {str(e)}"
        )


@router.post("/reject/{task_id}")
async def reject_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Child rejects a task (final decision)."""
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can reject tasks"
        )
    
    try:
        await firebase_service.reject_task(task_id)
        task = await firebase_service.get_task(task_id)
        return TaskResponse(**task)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to reject task: {str(e)}"
        )


@router.post("/schedule/{task_id}")
async def schedule_task(
    task_id: str,
    scheduled_data: dict,
    current_user: dict = Depends(get_current_user)
):
    """Child schedules a task for later."""
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can schedule tasks"
        )
    
    try:
        from datetime import datetime
        scheduled_time = datetime.fromisoformat(scheduled_data.get('scheduled_for'))
        
        await firebase_service.schedule_task(task_id, scheduled_time)
        task = await firebase_service.get_task(task_id)
        return TaskResponse(**task)
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
    """Delete a task (Parent or Child can delete)."""
    try:
        # Get task to verify ownership
        task = await firebase_service.get_task(task_id)
        
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found"
            )
        
        # Allow deletion if user is the creator (parent) or assigned child
        if current_user["id"] not in [task.get("created_by"), task.get("assigned_to")]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have permission to delete this task"
            )
        
        # Delete the task (soft delete - mark as deleted)
        await firebase_service.delete_task(task_id, current_user["id"])
        
        return {"message": "Task deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete task: {str(e)}"
        )

