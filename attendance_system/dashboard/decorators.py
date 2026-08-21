from functools import wraps
from django.shortcuts import redirect
from django.contrib import messages


def admin_required(view_func):
    """
    Only lets in authenticated Users with role == 'admin'.
    Anyone else (anonymous, student, teacher) is bounced to the
    dashboard login page. This is intentionally separate from
    Django's is_staff/is_superuser — those control Django admin
    (/admin/), this controls the AttendX dashboard (/dashboard/).
    """
    @wraps(view_func)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            return redirect('dashboard:login')
        if getattr(request.user, 'role', None) != 'admin':
            messages.error(request, "This dashboard is for admin accounts only.")
            return redirect('dashboard:login')
        return view_func(request, *args, **kwargs)
    return wrapper
