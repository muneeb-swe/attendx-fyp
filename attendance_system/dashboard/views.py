from django.contrib.auth import authenticate, login, logout
from django.contrib import messages
from django.shortcuts import render, redirect, get_object_or_404
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.core.paginator import Paginator

from users.models import Device, DeviceEvent, Student
from attendance.models import AttendanceRecord, Session, Class, Enrollment

from .decorators import admin_required


def dashboard_login(request):
    if request.user.is_authenticated and getattr(request.user, 'role', None) == 'admin':
        return redirect('dashboard:home')

    if request.method == 'POST':
        username = request.POST.get('username', '').strip()
        password = request.POST.get('password', '')
        user = authenticate(request, username=username, password=password)

        if user is None:
            messages.error(request, "Invalid username or password.")
        elif getattr(user, 'role', None) != 'admin':
            messages.error(request, "This account doesn't have admin access.")
        else:
            login(request, user)
            return redirect('dashboard:home')

    return render(request, 'dashboard/login.html')


@admin_required
def dashboard_logout(request):
    logout(request)
    return redirect('dashboard:login')


@admin_required
def home(request):
    records = AttendanceRecord.objects.all()

    total = records.count()
    present = records.filter(status='present').count()
    absent = records.filter(status='absent').count()

    modified = records.filter(is_modified=True).count()
    absent_to_present = records.filter(
        is_modified=True, original_status='absent', status='present'
    ).count()
    present_to_absent = records.filter(
        is_modified=True, original_status='present', status='absent'
    ).count()

    # Only meaningful among CURRENTLY present records: absent students
    # never scan, so "no signature" on an absent record is expected,
    # not suspicious. What actually matters is a record marked present
    # right now with no signature backing it — that means the "present"
    # came entirely from a teacher's manual edit, not a real scan.
    present_records = records.filter(status='present')
    present_with_proof = present_records.exclude(signature='').count()
    present_without_proof = present_records.filter(signature='').count()

    total_devices = Device.objects.count()
    active_devices = Device.objects.filter(is_active=True).count()
    disabled_devices = Device.objects.filter(is_active=False).count()
    mismatch_attempts = DeviceEvent.objects.filter(
        event_type__in=['mismatch_student_has_device', 'mismatch_fingerprint_taken']
    ).count()

    context = {
        'total': total, 'present': present, 'absent': absent,
        'modified': modified,
        'modified_pct': round(modified / total * 100, 1) if total else 0,
        'absent_to_present': absent_to_present,
        'present_to_absent': present_to_absent,
        'present_with_proof': present_with_proof,
        'present_without_proof': present_without_proof,
        'total_devices': total_devices,
        'active_devices': active_devices,
        'disabled_devices': disabled_devices,
        'mismatch_attempts': mismatch_attempts,
        'recent_events': DeviceEvent.objects.select_related(
            'student', 'conflicting_student', 'performed_by'
        )[:8],
    }
    return render(request, 'dashboard/home.html', context)


@admin_required
def device_list(request):
    devices = Device.objects.select_related('student', 'student__user').order_by('-registered_at')

    q = request.GET.get('q', '').strip()
    if q:
        devices = devices.filter(
            Q(student__roll_number__icontains=q) |
            Q(device_fingerprint__icontains=q) |
            Q(student__user__first_name__icontains=q) |
            Q(student__user__last_name__icontains=q)
        )

    status_filter = request.GET.get('status', '')
    if status_filter == 'active':
        devices = devices.filter(is_active=True)
    elif status_filter == 'disabled':
        devices = devices.filter(is_active=False)

    # Students who have never enrolled a device at all — the "null" case
    enrolled_student_ids = Device.objects.values_list('student_id', flat=True)
    never_enrolled = Student.objects.exclude(id__in=enrolled_student_ids)
    never_enrolled_q = request.GET.get('never_enrolled')
    if never_enrolled_q:
        never_enrolled = never_enrolled.filter(
            Q(roll_number__icontains=q) | Q(user__first_name__icontains=q) | Q(user__last_name__icontains=q)
        ) if q else never_enrolled

    paginator = Paginator(devices, 25)
    page_obj = paginator.get_page(request.GET.get('page'))

    context = {
        'page_obj': page_obj,
        'q': q,
        'status_filter': status_filter,
        'never_enrolled': never_enrolled if never_enrolled_q else None,
    }
    return render(request, 'dashboard/devices.html', context)


@admin_required
def device_detail(request, device_id):
    device = get_object_or_404(Device.objects.select_related('student', 'student__user'), id=device_id)
    events = device.events.select_related('performed_by', 'conflicting_student').order_by('-created_at')
    return render(request, 'dashboard/device_detail.html', {'device': device, 'events': events})


@admin_required
def device_toggle(request, device_id):
    """
    POST-only. Flips a device's is_active state and always writes a
    DeviceEvent — this is the ONLY code path that can change
    is_active from the dashboard, so the audit log can never be
    bypassed the way it could be by editing the field directly.
    """
    if request.method != 'POST':
        return redirect('dashboard:device_detail', device_id=device_id)

    device = get_object_or_404(Device, id=device_id)

    if device.is_active:
        device.is_active = False
        device.save(update_fields=['is_active'])
        DeviceEvent.objects.create(
            student=device.student, device=device, event_type='deactivated',
            device_fingerprint=device.device_fingerprint, performed_by=request.user,
        )
        messages.success(request, f"Disabled device for {device.student.roll_number}.")
    else:
        device.is_active = True
        try:
            with transaction.atomic():
                device.save(update_fields=['is_active'])
                DeviceEvent.objects.create(
                    student=device.student, device=device, event_type='reactivated',
                    device_fingerprint=device.device_fingerprint, performed_by=request.user,
                )
            messages.success(request, f"Enabled device for {device.student.roll_number}.")
        except IntegrityError:
            device.is_active = False  # local object still says True; correct it
            messages.error(
                request,
                "Can't enable — this student already has a different active "
                "device, or this fingerprint is active on another student."
            )

    return redirect('dashboard:device_detail', device_id=device_id)


@admin_required
def class_list(request):
    """
    Every class, with its enrolled-student count and session count.
    Entry point into the day-by-day transparency drill-down.
    """
    classes = Class.objects.select_related('teacher', 'teacher__user').all()
    data = []
    for c in classes:
        data.append({
            'obj': c,
            'enrolled_count': Enrollment.objects.filter(class_enrolled=c).count(),
            'session_count': Session.objects.filter(class_ref=c).count(),
        })
    return render(request, 'dashboard/class_list.html', {'classes': data})


@admin_required
def class_detail(request, class_id):
    """
    Every session ever held for this class, most recent first — the
    'day by day' view. Each row shows that day's present/absent/
    modified counts so an admin can spot an unusual day at a glance
    before drilling into it.
    """
    class_obj = get_object_or_404(Class, id=class_id)
    sessions = Session.objects.filter(class_ref=class_obj).order_by('-created_at')

    data = []
    for s in sessions:
        records = AttendanceRecord.objects.filter(session=s)
        data.append({
            'obj': s,
            'present': records.filter(status='present').count(),
            'absent': records.filter(status='absent').count(),
            'modified': records.filter(is_modified=True).count(),
            'total': records.count(),
        })

    return render(request, 'dashboard/class_detail.html', {
        'class_obj': class_obj, 'sessions': data,
    })


@admin_required
def session_detail(request, session_id):
    """
    The actual proof view. One row per enrolled student for this
    session: what they were originally marked as (with signature =
    proof they scanned), what they're marked as now, and whether a
    teacher changed it. This is what answers 'I marked attendance,
    the teacher changed it to absent, prove it' — original_status
    'present' + a non-empty signature is the student's proof, visible
    here regardless of what the current status says.
    """
    session = get_object_or_404(Session.objects.select_related('class_ref', 'teacher', 'teacher__user'), id=session_id)
    records = AttendanceRecord.objects.filter(session=session).select_related(
        'student', 'student__user', 'device'
    ).order_by('student__roll_number')

    return render(request, 'dashboard/session_detail.html', {
        'session': session, 'records': records,
    })


@admin_required
def event_log(request):
    events = DeviceEvent.objects.select_related(
        'student', 'conflicting_student', 'performed_by', 'device'
    ).order_by('-created_at')

    event_type = request.GET.get('type', '')
    if event_type:
        events = events.filter(event_type=event_type)

    q = request.GET.get('q', '').strip()
    if q:
        events = events.filter(
            Q(student__roll_number__icontains=q) | Q(device_fingerprint__icontains=q)
        )

    paginator = Paginator(events, 30)
    page_obj = paginator.get_page(request.GET.get('page'))

    return render(request, 'dashboard/events.html', {
        'page_obj': page_obj,
        'event_type': event_type,
        'q': q,
        'event_types': DeviceEvent.EVENT_TYPES,
    })
